import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'cert_exchange.dart';
import '../models/transfer_progress.dart';
import '../models/manifest_entry.dart';

/// Reads exact byte counts from a socket stream, buffering whatever
/// arrives early. Used for manifest, per-file headers, and file bytes
/// — all three are "read exactly N bytes" operations, just with
/// different N and different destinations (memory vs disk).
///
/// This replaces the old hand-rolled single-pass parser, which only
/// knew how to read one header + one file body. A multi-file manifest
/// needs to repeat "read a length-prefixed chunk" several times in a
/// row, so this small buffered reader is shared across all of them.
class _SocketReader {
  final Stream<List<int>> _stream;
  StreamIterator<List<int>>? _iterator;
  List<int> _buffer = [];

  _SocketReader(this._stream) {
    _iterator = StreamIterator(_stream);
  }

  /// Reads exactly [n] bytes, buffering across multiple socket chunks
  /// as needed. Returns null if the stream ends before [n] bytes
  /// arrive (sender disconnected early).
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

  /// Reads a [4-byte big-endian length][JSON payload] pair, as sent by
  /// FileSender._sendLengthPrefixedJson. Returns null on early EOF.
  Future<Map<String, dynamic>?> readLengthPrefixedJson() async {
    final lengthBytes = await readExact(4);
    if (lengthBytes == null) return null;
    final length =
        ByteData.sublistView(Uint8List.fromList(lengthBytes)).getUint32(0, Endian.big);
    final jsonBytes = await readExact(length);
    if (jsonBytes == null) return null;
    return jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
  }

  /// Streams exactly [n] bytes to [sink], calling [onChunk] after each
  /// write so the caller can report progress. Returns false on early
  /// EOF (fewer than [n] bytes arrived).
  Future<bool> pipeExact(
    int n,
    IOSink sink,
    void Function(int writtenSoFar) onChunk,
  ) async {
    var remaining = n;
    var written = 0;

    // Flush whatever's already buffered first.
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

      // Any leftover bytes beyond this file's size belong to the next
      // file's header — keep them buffered for the next readExact call.
      if (take < data.length) {
        _buffer = data.sublist(take);
      }
    }
    return true;
  }
}

/// Listens for incoming TLS-secured TCP connections and receives one
/// or more files per connection, using a manifest-first wire protocol
/// (Decision 013 — multi-file support).
///
/// Wire protocol:
/// 1. [4-byte length][manifest JSON: {type, count, files: [{name, size}]}]
/// 2. For each file, in order: [4-byte length][header JSON][file bytes]
///
/// A single-file send is just a manifest with one entry, so this
/// also handles the original Phase 2/3 use case with no special case.
class FileReceiver {
  final Directory targetDir;
  final String certPath;
  final String keyPath;
  final int port;

  /// Port for the small plain-TCP cert exchange server, started
  /// alongside the secure file-receiving server. See CertServer.
  final int certServerPort;

  final void Function(String message)? onStatus;
  final void Function(String ip, int port)? onConnection;

  /// Called when an incoming connection has to wait because another
  /// transfer is already in progress. [position] is how many transfers
  /// are ahead of it in the queue (1 = next up after the current one).
  final void Function(String ip, int position)? onQueued;

  final void Function(TransferProgress progress)? onProgress;

  /// Called once per file as it finishes (not once per batch).
  final void Function(String filename)? onComplete;

  /// Called once the whole batch (all files in the manifest) is done.
  final void Function(int fileCount)? onBatchComplete;

  final void Function(String message)? onError;

  /// Called once the incoming manifest is known (file count + total
  /// size), before any bytes are written to disk. Return true to
  /// accept and start receiving every file in the batch, false to
  /// reject the whole batch — in which case nothing is written.
  ///
  /// Optional — if not provided, behaves exactly as before (auto-accept).
  final Future<bool> Function(
    List<ManifestEntry> files,
    String senderIp,
  )? onIncomingRequest;

  /// How long to wait for an accept/reject decision before giving up
  /// and rejecting automatically.
  final Duration requestTimeout;

  /// Max time a connection will wait in queue before being dropped.
  final Duration queueTimeout;

  SecureServerSocket? _serverSocket;
  CertServer? _certServer;
  bool _running = false;

  /// Simple one-at-a-time lock for the actual file transfer step.
  /// The accept loop still accepts every incoming TCP connection right
  /// away — this lock only gates when a connection is allowed to start
  /// writing, so two transfers never interleave on disk at once.
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
    this.onIncomingRequest,
  });

  bool get isRunning => _running;

  /// Starts listening. Returns true if the server started successfully.
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

  /// Queues this connection behind any transfer already in progress,
  /// then runs it once it's this connection's turn (FIFO).
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
      onError?.call(
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

    try {
      final manifestJson = await reader.readLengthPrefixedJson();
      if (manifestJson == null) {
        onError?.call('Connection from $senderIp closed before sending a manifest.');
        return;
      }

      final filesJson = manifestJson['files'] as List<dynamic>;
      final manifestEntries = filesJson
          .map((e) => ManifestEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      if (manifestEntries.isEmpty) {
        onError?.call('Empty manifest from $senderIp — nothing to receive.');
        return;
      }

      // Ask whoever set up this receiver whether to accept the whole
      // batch — one decision covers every file in it (matches the
      // "1-2 clicks" goal; no per-file prompts).
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
        onError?.call(
            'Transfer of ${manifestEntries.length} file(s) from $senderIp was rejected.');
        return;
      }

      // Receive each file in order, exactly as described in the manifest.
      for (var i = 0; i < manifestEntries.length; i++) {
        final headerJson = await reader.readLengthPrefixedJson();
        if (headerJson == null) {
          onError?.call(
              'Connection from $senderIp closed early — expected ${manifestEntries.length} file(s), got $i.');
          return;
        }

        final filename = headerJson['filename'] as String;
        final totalSize = headerJson['size'] as int;

        final file = File('${targetDir.path}/$filename');
        final fileSink = file.openWrite();

        final completedFully = await reader.pipeExact(
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

        await fileSink.flush();
        await fileSink.close();

        if (!completedFully) {
          onError?.call(
              'Connection from $senderIp closed mid-transfer of "$filename".');
          return;
        }

        onComplete?.call(filename);
      }

      onBatchComplete?.call(manifestEntries.length);
    } catch (e) {
      onError?.call('Error during transfer: $e');
    } finally {
      socket.destroy();
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
