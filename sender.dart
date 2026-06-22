import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: dart sender.dart <receiver_ip> <file_path> <receiver_cert.pem>');
    exit(1);
  }

  final receiverIp = args[0];
  final filePath = args[1];
  final receiverCertPath = args[2];

  final file = File(filePath);
  if (!await file.exists()) {
    print('Error: File "$filePath" does not exist.');
    exit(1);
  }

  final certFile = File(receiverCertPath);
  if (!await certFile.exists()) {
    print('Error: Receiver certificate not found: $receiverCertPath');
    exit(1);
  }

  // Compute the expected SHA-256 fingerprint from the cert file on disk
  final expectedFingerprint = await computeCertFingerprint(receiverCertPath);
  print('Expected cert fingerprint: $expectedFingerprint');

  final filename = file.uri.pathSegments.last;
  final totalSize = await file.length();

  // Build a SecurityContext that trusts ONLY the receiver's cert
  final context = SecurityContext()
    ..setTrustedCertificates(receiverCertPath);

  print('Connecting to $receiverIp:7979 (TLS)...');

  late SecureSocket socket;
  try {
    socket = await SecureSocket.connect(
      receiverIp,
      7979,
      context: context,
      onBadCertificate: (X509Certificate cert) {
        // Called when the cert doesn't pass standard validation.
        // We do our own fingerprint check here instead.
        final presented = sha256
            .convert(cert.der)
            .bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(':');

        if (presented == expectedFingerprint) {
          print('Certificate fingerprint verified ✓');
          return true; // allow the connection
        } else {
          print('ERROR: Certificate fingerprint mismatch!');
          print('  Expected : $expectedFingerprint');
          print('  Presented: $presented');
          return false; // abort — this will throw a HandshakeException
        }
      },
    );
  } on HandshakeException catch (e) {
    print('TLS handshake failed — aborting. No data was sent.');
    print('Detail: $e');
    exit(1);
  } catch (e) {
    print('Error connecting to $receiverIp: $e');
    exit(1);
  }

  print('Connected securely to $receiverIp:7979 (TLS)');

  final headerMap = {
    'filename': filename,
    'size': totalSize,
  };
  final headerJson = jsonEncode(headerMap);
  final headerBytes = utf8.encode(headerJson);

  final lengthByteData = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);
  socket.add(lengthByteData.buffer.asUint8List());
  socket.add(headerBytes);

  int bytesSent = 0;
  final fileStream = file.openRead();

  await for (final chunk in fileStream) {
    socket.add(chunk);
    bytesSent += chunk.length;
    final sentMB = (bytesSent / (1024 * 1024)).toStringAsFixed(2);
    final totalMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);
    stdout.write('\rSending $filename — $sentMB MB / $totalMB MB');
  }

  await socket.flush();
  await socket.close();
  print('\nTransfer complete: $filename');
}

/// Reads a PEM cert file and returns its SHA-256 fingerprint as a hex string
/// in the format: aa:bb:cc:...
Future<String> computeCertFingerprint(String certPath) async {
  final pemBytes = await File(certPath).readAsBytes();

  // Strip PEM headers and decode base64 to get raw DER bytes
  final pemString = utf8.decode(pemBytes);
  final base64Body = pemString
      .replaceAll('-----BEGIN CERTIFICATE-----', '')
      .replaceAll('-----END CERTIFICATE-----', '')
      .replaceAll('\n', '')
      .replaceAll('\r', '')
      .trim();

  final derBytes = base64Decode(base64Body);
  final digest = sha256.convert(derBytes);
  return digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(':');
}
