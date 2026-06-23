import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../models/transfer_progress.dart';
import '../models/manifest_entry.dart';

/// Sends one or more files to a receiver over a single TLS-secured TCP
/// connection, verifying the receiver's certificate by SHA-256
/// fingerprint first (no accounts/login — Decision 003).
///
/// Wire protocol (Decision 013 — multi-file manifest):
/// 1. [4-byte length][manifest JSON: {type: "manifest", files: [...], count: N}]
/// 2. For each file, in order: [4-byte length][file header JSON][file bytes]
/// 3. Connection closes after the last file
///
/// A single-file send is just a manifest with one entry — no special
/// case needed. Connection setup (TLS handshake, fingerprint check) is
/// unchanged from the original single-file version.
class FileSender {
  final String receiverIp;
  final int port;
  final List<String> filePaths;
  final String receiverCertPath;

  final void Function(String message)? onStatus;

  /// Called once per chunk of bytes sent, for whichever file is
  /// currently in flight. progress.fileIndex/fileCount tell you which
  /// file in the batch this is (1-based).
  final void Function(TransferProgress progress)? onProgress;

  final void Function()? onComplete;

  /// Called on any failure: missing file, missing cert, handshake
  /// failure, fingerprint mismatch, or connection error.
  final void Function(String message)? onError;

  FileSender({
    required this.receiverIp,
    required this.filePaths,
    required this.receiverCertPath,
    this.port = 7979,
    this.onStatus,
    this.onProgress,
    this.onComplete,
    this.onError,
  }) : assert(filePaths.length > 0, 'filePaths must not be empty');

  /// Convenience constructor for the common single-file case — same
  /// call shape as the old FileSender(filePath: ...) had, so existing
  /// callers (CLI sender.dart, send_screen.dart) only need a one-word
  /// change (filePath -> filePaths: [path]) rather than a rewrite.
  factory FileSender.single({
    required String receiverIp,
    required String filePath,
    required String receiverCertPath,
    int port = 7979,
    void Function(String message)? onStatus,
    void Function(TransferProgress progress)? onProgress,
    void Function()? onComplete,
    void Function(String message)? onError,
  }) {
    return FileSender(
      receiverIp: receiverIp,
      filePaths: [filePath],
      receiverCertPath: receiverCertPath,
      port: port,
      onStatus: onStatus,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
    );
  }

  /// Runs the full send flow for every file in [filePaths], over one
  /// connection. Returns true only if every file sent successfully.
  /// Never throws and never calls exit() — caller decides what to do.
  Future<bool> send() async {
    // Validate every file exists before opening any connection — fail
    // fast rather than connecting and aborting partway through.
    final files = <File>[];
    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) {
        onError?.call('File "$path" does not exist.');
        return false;
      }
      files.add(file);
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
            return true;
          } else {
            onStatus?.call('Certificate fingerprint mismatch');
            return false;
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
      // Step 1 — send the manifest describing every file in this batch.
      final manifestEntries = <ManifestEntry>[];
      for (final file in files) {
        manifestEntries.add(ManifestEntry(
          name: file.uri.pathSegments.last,
          size: await file.length(),
        ));
      }

      final manifestMap = {
        'type': 'manifest',
        'count': manifestEntries.length,
        'files': manifestEntries.map((e) => e.toJson()).toList(),
      };
      await _sendLengthPrefixedJson(socket, manifestMap);
      onStatus?.call('Sent manifest: ${manifestEntries.length} file(s)');

      // Step 2 — send each file in order, same per-file format as the
      // original single-file protocol (length-prefixed header + bytes).
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final entry = manifestEntries[i];

        final headerMap = {'filename': entry.name, 'size': entry.size};
        await _sendLengthPrefixedJson(socket, headerMap);

        int bytesSent = 0;
        final fileStream = file.openRead();
        await for (final chunk in fileStream) {
          socket.add(chunk);
          bytesSent += chunk.length;
          onProgress?.call(TransferProgress(
            filename: entry.name,
            bytesDone: bytesSent,
            totalBytes: entry.size,
            fileIndex: i + 1,
            fileCount: files.length,
          ));
        }
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

  Future<void> _sendLengthPrefixedJson(
      SecureSocket socket, Map<String, dynamic> data) async {
    final bytes = utf8.encode(jsonEncode(data));
    final lengthByteData = ByteData(4)..setUint32(0, bytes.length, Endian.big);
    socket.add(lengthByteData.buffer.asUint8List());
    socket.add(bytes);
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
