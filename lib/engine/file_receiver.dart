import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

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

  final void Function(String message)? onStatus;
  final void Function(String ip, int port)? onConnection;
  final void Function(TransferProgress progress)? onProgress;
  final void Function(String filename)? onComplete;
  final void Function(String message)? onError;

  SecureServerSocket? _serverSocket;
  bool _running = false;

  FileReceiver({
    required this.targetDir,
    required this.certPath,
    required this.keyPath,
    this.port = 7979,
    this.onStatus,
    this.onConnection,
    this.onProgress,
    this.onComplete,
    this.onError,
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

    _acceptLoop();
    return true;
  }

  void _acceptLoop() async {
    await for (final socket in _serverSocket!) {
      onConnection?.call(socket.remoteAddress.address, socket.remotePort);
      await _handleConnection(socket);
    }
  }

  Future<void> _handleConnection(SecureSocket socket) async {
    try {
      final bytesBuilder = BytesBuilder();
      int? headerLength;
      Map<String, dynamic>? header;
      IOSink? fileSink;
      String? filename;
      int? totalSize;
      int fileBytesReceived = 0;
      bool headerParsed = false;

      await for (final data in socket) {
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

            final file = File('${targetDir.path}/$filename');
            fileSink = file.openWrite();
            headerParsed = true;

            final remaining = buffer.sublist(headerLength);
            if (remaining.isNotEmpty) {
              fileSink.add(remaining);
              fileBytesReceived += remaining.length;
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
    onStatus?.call('Shutting down server...');
  }
}
