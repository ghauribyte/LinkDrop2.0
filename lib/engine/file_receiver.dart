import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'cert_exchange.dart';
import '../models/transfer_progress.dart';
import '../models/manifest_entry.dart';

/// Reads exact byte counts from a socket stream, buffering whatever
/// arrives early. Used for manifest, per-file headers, and file bytes.
class _SocketReader {
  final Stream<List<int>> _stream;
  StreamIterator<List<int>>? _iterator;
  List<int> _buffer = [];

  _SocketReader(this._stream) {
    _iterator = StreamIterator(_stream);
  }

  Future<List<int>?> readExact(int n) async {
    while (_buffer.length < n) {
      final hasMore = await _iterator!.moveNext();
      if (!hasMore) return null;
      _buffer.addAll(_iterator!.current);
    }
    final result = _buffer.sublist(0, n);
    _buffer = _buffer.sublist(n);
    return result;
  }

  Future<Map<String, dynamic>?> readLengthPrefixedJson() async {
    final lengthBytes = await readExact(4);
    if (lengthBytes == null) return null;
    final length =
        ByteData.sublistView(Uint8List.fromList(lengthBytes)).getUint32(0, Endian.big);
    if (length <= 0 || length > 10 * 1024 * 1024) {
      throw FormatException('Invalid header length: $length');
    }
    final jsonBytes = await readExact(length);
    if (jsonBytes == null) return null;
    return jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
  }

  Future<bool> pipeExact(
    int n,
    IOSink sink,
    void Function(int writtenSoFar) onChunk,
  ) async {
    var remaining = n;
    var written = 0;

    if (_buffer.isNotEmpty) {
      final take = _buffer.length < remaining ? _buffer.length : remaining;
      final chunk = _buffer.sublist(0, take);
      _buffer = _buffer.sublist(take);
      sink.add(chunk);
      written += chunk.length;
      remaining -= chunk.length;
      onChunk(written);
    }

    while (remaining > 0) {
      final hasMore = await _iterator!.moveNext();
      if (!hasMore) return false;
      final data = _iterator!.current;
      final take = data.length < remaining ? data.length : remaining;
      sink.add(data.sublist(0, take));
      written += take;
      remaining -= take;
      onChunk(written);

      if (take < data.length) {
        _buffer = data.sublist(take);
      }
    }
    return true;
  }
}

/// Removes path separators and traversal sequences from a filename
/// received over the network, so a malicious/buggy sender can never
/// write outside targetDir (e.g. "../../etc/passwd" or "/etc/passwd").
/// Keeps only the final path segment, then strips any remaining ".."
String _sanitizeFilename(String name) {
  final base = name.split(RegExp(r'[\\/]')).last;
  final cleaned = base.replaceAll('..', '_').trim();
  return cleaned.isEmpty ? 'unnamed_file' : cleaned;
}

/// Listens for incoming TLS-secured TCP connections and receives one
/// or more files per connection, using a manifest-first wire protocol
/// (Decision 013 — multi-file support).
class FileReceiver {
  final Directory targetDir;
  final String certPath;
  final String keyPath;
  final int port;
  final int certServerPort;

  final void Function(String message)? onStatus;
  final void Function(String ip, int port)? onConnection;
  final void Function(String ip, int position)? onQueued;
  final void Function(TransferProgress progress)? onProgress;
  final void Function(String filename)? onComplete;
  final void Function(int fileCount)? onBatchComplete;

  /// True failures: bad network, disk full, write error, malformed
  /// protocol. Not used for expected outcomes like a user rejecting.
  final void Function(String message)? onError;

  /// Expected, non-error outcomes: user rejected, queue timeout,
  /// sender disconnected early. Kept separate from onError so the
  /// GUI doesn't have to guess which messages are "real" failures.
  final void Function(String message)? onRejected;

  final Future<bool> Function(
    List<ManifestEntry> files,
    String senderIp,
  )? onIncomingRequest;

  final Duration requestTimeout;
  final Duration queueTimeout;

  SecureServerSocket? _serverSocket;
  CertServer? _certServer;
  bool _running = false;

  Future<void> _transferLock = Future.value();
  int _queueLength = 0;

  FileReceiver({
    required this.targetDir,
    required this.certPath,
    required this.keyPath,
    this.port = 7979,
    this.certServerPort = 7980,
    this.queueTimeout = const Duration(minutes: 5),
    this.requestTimeout = const Duration(seconds: 60),
    this.onStatus,
    this.onConnection,
    this.onQueued,
    this.onProgress,
    this.onComplete,
    this.onBatchComplete,
    this.onError,
    this.onRejected,
    this.onIncomingRequest,
  });

  bool get isRunning => _running;

  Future<bool> start() async {
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    if (!await File(certPath).exists()) {
      onError?.call('Certificate file not found: $certPath');
      return false;
    }
    if (!await File(keyPath).exists()) {
      onError?.call('Key file not found: $keyPath');
      return false;
    }

    final context = SecurityContext()
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);

    try {
      _serverSocket = await SecureServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        context,
      );
    } catch (e) {
      onError?.call('Could not start secure receiver: $e');
      return false;
    }

    _running = true;
    onStatus?.call('Secure receiver listening on port $port (TLS)');

    _certServer = CertServer(
      certPath: certPath,
      port: certServerPort,
      onStatus: onStatus,
      onError: onError,
    );
    await _certServer!.start();

    _acceptLoop();
    return true;
  }

  void _acceptLoop() async {
    await for (final socket in _serverSocket!) {
      onConnection?.call(socket.remoteAddress.address, socket.remotePort);
      _queueAndHandle(socket);
    }
  }

  Future<void> _queueAndHandle(SecureSocket socket) async {
    final myTurn = _transferLock;
    final position = _queueLength;
    _queueLength++;

    final completer = Completer<void>();
    _transferLock = completer.future;

    if (position > 0) {
      onQueued?.call(socket.remoteAddress.address, position);
    }

    try {
      await myTurn.timeout(queueTimeout);
    } catch (_) {
      onRejected?.call(
          'Transfer from ${socket.remoteAddress.address} timed out waiting in queue.');
      socket.destroy();
      _queueLength--;
      completer.complete();
      return;
    }

    try {
      await _handleConnection(socket);
    } finally {
      _queueLength--;
      completer.complete();
    }
  }

  Future<void> _handleConnection(SecureSocket socket) async {
    final senderIp = socket.remoteAddress.address;
    final reader = _SocketReader(socket);
    File? partialFile;

    try {
      final manifestJson = await reader.readLengthPrefixedJson();
      if (manifestJson == null) {
        onRejected?.call('Connection from $senderIp closed before sending a manifest.');
        return;
      }

      final filesJson = manifestJson['files'];
      if (filesJson is! List || filesJson.isEmpty) {
        onError?.call('Malformed or empty manifest from $senderIp.');
        return;
      }

      final List<ManifestEntry> manifestEntries;
      try {
        manifestEntries = filesJson
            .map((e) => ManifestEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        onError?.call('Malformed manifest entry from $senderIp: $e');
        return;
      }

      for (final entry in manifestEntries) {
        if (entry.size < 0) {
          onError?.call('Manifest from $senderIp has invalid size for "${entry.name}".');
          return;
        }
      }

      bool accepted = true;
      if (onIncomingRequest != null) {
        try {
          accepted = await onIncomingRequest!(manifestEntries, senderIp)
              .timeout(requestTimeout);
        } catch (_) {
          accepted = false;
        }
      }

      if (!accepted) {
        onRejected?.call(
            'Transfer of ${manifestEntries.length} file(s) from $senderIp was rejected.');
        return;
      }

      for (var i = 0; i < manifestEntries.length; i++) {
        final headerJson = await reader.readLengthPrefixedJson();
        if (headerJson == null) {
          onRejected?.call(
              'Connection from $senderIp closed early — expected ${manifestEntries.length} file(s), got $i.');
          return;
        }

        final rawFilename = headerJson['filename'];
        final rawSize = headerJson['size'];
        if (rawFilename is! String || rawSize is! int || rawSize < 0) {
          onError?.call('Malformed file header from $senderIp at file ${i + 1}.');
          return;
        }

        final filename = _sanitizeFilename(rawFilename);
        final totalSize = rawSize;

        final file = File('${targetDir.path}/$filename');
        partialFile = file;

        IOSink fileSink;
        try {
          fileSink = file.openWrite();
        } catch (e) {
          onError?.call('Could not write "$filename": $e');
          return;
        }

        bool completedFully;
        try {
          completedFully = await reader.pipeExact(
            totalSize,
            fileSink,
            (writtenSoFar) {
              onProgress?.call(TransferProgress(
                filename: filename,
                bytesDone: writtenSoFar,
                totalBytes: totalSize,
                fileIndex: i + 1,
                fileCount: manifestEntries.length,
              ));
            },
          );
        } catch (e) {
          await fileSink.close();
          await _deletePartial(file);
          onError?.call('Write failed for "$filename" (disk full or I/O error): $e');
          return;
        }

        await fileSink.flush();
        await fileSink.close();

        if (!completedFully) {
          await _deletePartial(file);
          onRejected?.call(
              'Connection from $senderIp closed mid-transfer of "$filename".');
          return;
        }

        partialFile = null;
        onComplete?.call(filename);
      }

      onBatchComplete?.call(manifestEntries.length);
    } catch (e) {
      if (partialFile != null) {
        await _deletePartial(partialFile);
      }
      onError?.call('Error during transfer from $senderIp: $e');
    } finally {
      socket.destroy();
    }
  }

  Future<void> _deletePartial(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup — ignore if delete itself fails.
    }
  }

  Future<void> stop() async {
    _running = false;
    await _serverSocket?.close();
    _serverSocket = null;
    await _certServer?.stop();
    _certServer = null;
    onStatus?.call('Shutting down server...');
  }
}
