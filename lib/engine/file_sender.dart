import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/transfer_progress.dart';

/// Sends a file to a receiver over a TLS-secured TCP connection,
/// verifying the receiver's certificate by SHA-256 fingerprint first
/// (no accounts/login — Decision 003, trust via cert fingerprint).
///
/// Same protocol and verification logic as the original sender.dart —
/// only the input/output style changed (callbacks + return values
/// instead of print/exit) so this can be driven by a CLI script or
/// a Flutter UI.
class FileSender {
  final String receiverIp;
  final int port;
  final String filePath;
  final String receiverCertPath;

  final void Function(String message)? onStatus;
  final void Function(TransferProgress progress)? onProgress;
  final void Function()? onComplete;

  /// Called on any failure: missing file, missing cert, handshake
  /// failure, fingerprint mismatch, or connection error.
  /// The CLI wrapper can print + exit(1); Flutter can show a popup.
  final void Function(String message)? onError;

  FileSender({
    required this.receiverIp,
    required this.filePath,
    required this.receiverCertPath,
    this.port = 7979,
    this.onStatus,
    this.onProgress,
    this.onComplete,
    this.onError,
  });

  /// Runs the full send flow. Returns true on success, false on failure.
  /// Never throws and never calls exit() — caller decides what to do.
  Future<bool> send() async {
    final file = File(filePath);
    if (!await file.exists()) {
      onError?.call('File "$filePath" does not exist.');
      return false;
    }

    final certFile = File(receiverCertPath);
    if (!await certFile.exists()) {
      onError?.call('Receiver certificate not found: $receiverCertPath');
      return false;
    }

    final String expectedFingerprint;
    try {
      expectedFingerprint = await _computeCertFingerprint(receiverCertPath);
    } catch (e) {
      onError?.call('Could not read receiver certificate: $e');
      return false;
    }
    onStatus?.call('Expected cert fingerprint: $expectedFingerprint');

    final filename = file.uri.pathSegments.last;
    final totalSize = await file.length();

    final context = SecurityContext()..setTrustedCertificates(receiverCertPath);

    onStatus?.call('Connecting to $receiverIp:$port (TLS)...');

    SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        receiverIp,
        port,
        context: context,
        onBadCertificate: (X509Certificate cert) {
          final presented = sha256
              .convert(cert.der)
              .bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(':');

          if (presented == expectedFingerprint) {
            onStatus?.call('Certificate fingerprint verified');
            return true; // allow the connection
          } else {
            onStatus?.call('Certificate fingerprint mismatch');
            return false; // abort — throws HandshakeException
          }
        },
      );
    } on HandshakeException catch (e) {
      onError?.call('TLS handshake failed — aborting. No data was sent. ($e)');
      return false;
    } catch (e) {
      onError?.call('Error connecting to $receiverIp: $e');
      return false;
    }

    onStatus?.call('Connected securely to $receiverIp:$port (TLS)');

    try {
      final headerMap = {'filename': filename, 'size': totalSize};
      final headerBytes = utf8.encode(jsonEncode(headerMap));

      final lengthByteData = ByteData(4)
        ..setUint32(0, headerBytes.length, Endian.big);
      socket.add(lengthByteData.buffer.asUint8List());
      socket.add(headerBytes);

      int bytesSent = 0;
      final fileStream = file.openRead();

      await for (final chunk in fileStream) {
        socket.add(chunk);
        bytesSent += chunk.length;
        onProgress?.call(TransferProgress(
          filename: filename,
          bytesDone: bytesSent,
          totalBytes: totalSize,
        ));
      }

      await socket.flush();
      await socket.close();
      onComplete?.call();
      return true;
    } catch (e) {
      onError?.call('Error during transfer: $e');
      socket.destroy();
      return false;
    }
  }

  /// Reads a PEM cert file and returns its SHA-256 fingerprint as a hex
  /// string in the format: aa:bb:cc:...
  Future<String> _computeCertFingerprint(String certPath) async {
    final pemBytes = await File(certPath).readAsBytes();
    final pemString = utf8.decode(pemBytes);
    final base64Body = pemString
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();

    final derBytes = base64Decode(base64Body);
    final digest = sha256.convert(derBytes);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }
}
