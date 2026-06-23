import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A tiny, deliberately simple plain-TCP server that hands out this
/// device's certificate file (cert.pem) to anyone who asks.
///
/// This is NOT a security boundary — handing out a public certificate
/// is exactly as safe as putting it on a public website. The actual
/// trust check still happens later, in FileSender, via SHA-256
/// fingerprint verification at TLS connect time (Decision 003).
/// This server's only job is to remove the manual "copy cert.pem by
/// hand" step from the send flow.
///
/// Wire protocol: client connects, server immediately writes the raw
/// bytes of cert.pem, then closes the connection. No request needed —
/// connecting IS the request.
class CertServer {
  final String certPath;
  final int port;

  final void Function(String message)? onStatus;
  final void Function(String message)? onError;

  ServerSocket? _serverSocket;
  bool _running = false;

  CertServer({
    required this.certPath,
    this.port = 7980,
    this.onStatus,
    this.onError,
  });

  bool get isRunning => _running;

  Future<bool> start() async {
    if (!await File(certPath).exists()) {
      onError?.call('Cannot start cert server — certificate not found: $certPath');
      return false;
    }

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    } catch (e) {
      onError?.call('Could not start cert server: $e');
      return false;
    }

    _running = true;
    onStatus?.call('Cert server listening on port $port (plain TCP, public cert only)');

    _acceptLoop();
    return true;
  }

  void _acceptLoop() async {
    await for (final socket in _serverSocket!) {
      _handleRequest(socket);
    }
  }

  Future<void> _handleRequest(Socket socket) async {
    try {
      final certBytes = await File(certPath).readAsBytes();
      socket.add(certBytes);
      await socket.flush();
    } catch (e) {
      onError?.call('Error serving cert request: $e');
    } finally {
      await socket.close();
    }
  }

  Future<void> stop() async {
    _running = false;
    await _serverSocket?.close();
    _serverSocket = null;
    onStatus?.call('Cert server stopped');
  }
}

/// Connects to [ip]:[port] and downloads the certificate being served
/// by [CertServer] there. Returns the raw PEM text, or null on failure.
///
/// This is the client half — used by the sender right before calling
/// FileSender, so the person doesn't have to manually copy cert.pem
/// from the receiver's machine anymore.
Future<String?> fetchCert({
  required String ip,
  int port = 7980,
  Duration timeout = const Duration(seconds: 5),
}) async {
  Socket socket;
  try {
    socket = await Socket.connect(ip, port, timeout: timeout);
  } catch (e) {
    return null;
  }

  try {
    final bytes = await socket.fold<List<int>>(
      <int>[],
      (previous, chunk) => previous..addAll(chunk),
    ).timeout(timeout);

    final pemText = utf8.decode(bytes);

    // Basic sanity check — make sure we actually got a PEM cert back,
    // not some unrelated garbage from a port that happened to be open.
    if (!pemText.contains('-----BEGIN CERTIFICATE-----')) {
      return null;
    }

    return pemText;
  } catch (e) {
    return null;
  } finally {
    socket.destroy();
  }
}
