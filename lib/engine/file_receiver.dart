import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'cert_exchange.dart';
import '../models/transfer_progress.dart';

/// Listens for incoming TLS-secured TCP connections and receives a file,
/// using the same header-then-bytes wire format as FileSender.
///
/// Same protocol as the original receiver.dart — only the input/output
/// style changed (callbacks instead of print/exit) so this can be
/// driven by a CLI script or a Flutter UI (e.g. accept/reject popup
/// in Phase 4).
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
  final void Function(String filename)? onComplete;
  final void Function(String message)? onError;

  /// Called once the incoming file's name and size are known, before
  /// any bytes are written to disk. Return true to accept and start
  /// writing the file, false to reject — in which case nothing is
  /// written and the connection is closed.
  ///
  /// Optional — if not provided, behaves exactly as before (auto-accept,
  /// no behavior change), which keeps the CLI receiver.dart working
  /// unchanged. The GUI passes this to show an accept/reject popup.
  final Future<bool> Function(String filename, int size, String senderIp)?
      onIncomingRequest;

  /// How long to wait for an accept/reject decision before giving up
  /// and rejecting automatically. Prevents a sender being stuck forever
  /// if nobody looks at the popup.
  final Duration requestTimeout;

  /// Max time a connection will wait in queue before being dropped.
  /// Prevents one stuck/slow sender from blocking everyone forever.
  final Duration queueTimeout;

  SecureServerSocket? _serverSocket;
  CertServer? _certServer;
  bool _running = false;

  /// Simple one-at-a-time lock for the actual file transfer step.
  /// The accept loop still accepts every incoming TCP connection right
  /// away (so senders never get connection-refused) — this lock only
  /// gates when a connection is allowed to start writing its file,
  /// so two transfers never interleave on disk at once.
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

    // Start the small cert exchange server too, so senders can fetch
    // our public cert automatically instead of needing it copied by
    // hand. Same lifecycle as the main server — both start together.
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
      // Don't await here — accepting new TCP connections must never
      // block on a transfer that's already in progress. Queueing is
      // handled inside _queueAndHandle via _transferLock.
      _queueAndHandle(socket);
    }
  }

  /// Queues this connection behind any transfer already in progress,
  /// then runs it once it's this connection's turn. Connections are
  /// served strictly in the order they arrived (FIFO).
  Future<void> _queueAndHandle(SecureSocket socket) async {
    final myTurn = _transferLock;
    final position = _queueLength;
    _queueLength++;

    // Chain the next lock onto this one — the next caller waits for
    // this transfer (and everyone ahead of it) to finish first.
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
    try {
      final bytesBuilder = BytesBuilder();
      int? headerLength;
      Map<String, dynamic>? header;
      IOSink? fileSink;
      String? filename;
      int? totalSize;
      int fileBytesReceived = 0;
      bool headerParsed = false;
      bool rejected = false;

      // Bytes that arrive in the same chunk as the header tail need to
      // be held until the accept/reject decision is made, then either
      // written (accepted) or discarded (rejected).
      List<int>? pendingBytesAfterHeader;

      await for (final data in socket) {
        if (rejected) break;

        if (!headerParsed) {
          bytesBuilder.add(data);

          if (headerLength == null && bytesBuilder.length >= 4) {
            final buffer = bytesBuilder.takeBytes();
            final byteData =
                ByteData.sublistView(Uint8List.fromList(buffer.sublist(0, 4)));
            headerLength = byteData.getUint32(0, Endian.big);
            bytesBuilder.add(buffer.sublist(4));
          }

          if (headerLength != null && bytesBuilder.length >= headerLength) {
            final buffer = bytesBuilder.takeBytes();
            final jsonBytes = buffer.sublist(0, headerLength);
            final jsonStr = utf8.decode(jsonBytes);
            header = jsonDecode(jsonStr);
            filename = header!['filename'];
            totalSize = header['size'];
            headerParsed = true;
            pendingBytesAfterHeader = buffer.sublist(headerLength);

            // Ask whoever set up this receiver whether to accept this
            // file — the GUI shows a popup here; the CLI (no callback
            // provided) accepts automatically, same as before.
            bool accepted = true;
            if (onIncomingRequest != null) {
              try {
                accepted = await onIncomingRequest!(
                  filename!,
                  totalSize!,
                  senderIp,
                ).timeout(requestTimeout);
              } catch (_) {
                accepted = false; // timed out or threw — treat as reject
              }
            }

            if (!accepted) {
              rejected = true;
              onError?.call('Transfer of "$filename" from $senderIp was rejected.');
              break;
            }

            final file = File('${targetDir.path}/$filename');
            fileSink = file.openWrite();

            if (pendingBytesAfterHeader.isNotEmpty) {
              fileSink.add(pendingBytesAfterHeader);
              fileBytesReceived += pendingBytesAfterHeader.length;
              onProgress?.call(TransferProgress(
                filename: filename!,
                bytesDone: fileBytesReceived,
                totalBytes: totalSize!,
              ));
            }
          }
        } else {
          fileSink!.add(data);
          fileBytesReceived += data.length;
          onProgress?.call(TransferProgress(
            filename: filename!,
            bytesDone: fileBytesReceived,
            totalBytes: totalSize!,
          ));
        }
      }

      if (rejected) {
        return;
      }

      if (fileSink != null) {
        await fileSink.flush();
        await fileSink.close();
        onComplete?.call(filename!);
      }
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
