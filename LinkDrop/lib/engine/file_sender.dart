import 'dart:async';
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
  /// Minimum gap between progress callbacks. Each one drives setState on
  /// the GUI, so this is what keeps rendering from throttling the transfer.
  static const _progressInterval = Duration(milliseconds: 100);

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

  /// Called whenever the paused state flips, so a GUI can swap its
  /// pause/resume button without tracking the state itself.
  final void Function(bool isPaused)? onPausedChanged;

  FileSender({
    required this.receiverIp,
    required this.filePaths,
    required this.receiverCertPath,
    this.port = 7979,
    this.onStatus,
    this.onProgress,
    this.onComplete,
    this.onError,
    this.onPausedChanged,
  });

  // ---- pause / resume / cancel ----
  //
  // Pause works purely by stopping the feed into the socket: the socket
  // and the whole batch stay open, and the receiver's read simply blocks
  // waiting for bytes that aren't coming yet. Nothing about the wire
  // protocol changes, and no partial file is ever left behind, so the
  // receiver invariants in Decision 014 still hold untouched.
  //
  // Note this is *in-session* pause only — it survives an arbitrarily
  // long pause but not a dropped connection. Resuming across a
  // reconnect would need offset negotiation in the protocol AND would
  // directly conflict with the receiver's "delete partials on early
  // disconnect" rule, so it's deliberately not attempted here.

  bool _paused = false;
  bool _cancelled = false;
  Completer<void>? _resumeSignal;

  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;

  /// Halts the byte feed at the next chunk boundary. Safe to call when
  /// already paused or when no transfer is running (both are no-ops).
  void pause() {
    if (_paused || _cancelled) return;
    _paused = true;
    _resumeSignal = Completer<void>();
    onStatus?.call('Transfer paused.');
    onPausedChanged?.call(true);
  }

  /// Continues a paused transfer from exactly where it stopped.
  void resume() {
    if (!_paused) return;
    _paused = false;
    // Guard against double-complete if resume() races cancel().
    if (_resumeSignal != null && !_resumeSignal!.isCompleted) {
      _resumeSignal!.complete();
    }
    _resumeSignal = null;
    onStatus?.call('Transfer resumed.');
    onPausedChanged?.call(false);
  }

  /// Aborts the transfer. If currently paused, this also releases the
  /// paused send loop so it can observe the cancellation and unwind
  /// rather than hanging forever.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (_paused) resume();
  }

  /// Blocks the send loop while paused. Returns as soon as the transfer
  /// is resumed or cancelled.
  Future<void> _waitWhilePaused() async {
    while (_paused && !_cancelled) {
      final signal = _resumeSignal;
      if (signal == null) break;
      await signal.future;
    }
  }

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
    if (filePaths.isEmpty) {
      onError?.call('No files to send.');
      return false;
    }

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

    // Nagle's algorithm holds small writes back waiting to coalesce them.
    // Every write here is already a large block, so that delay buys
    // nothing and adds latency at each flush boundary.
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {
      // Not supported everywhere; the transfer works without it.
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
        // Also honour a pause/cancel between files, not just mid-file —
        // otherwise pausing during a batch would still push the next
        // file's header out before actually stopping.
        await _waitWhilePaused();
        if (_cancelled) {
          onStatus?.call('Transfer cancelled.');
          socket.destroy();
          return false;
        }

        final file = files[i];
        final entry = manifestEntries[i];

        final headerMap = {'filename': entry.name, 'size': entry.size};
        await _sendLengthPrefixedJson(socket, headerMap);

        int bytesSent = 0;
        var lastProgressAt = DateTime.now();
        try {
          final fileStream = file.openRead();
          await for (final chunk in fileStream) {
            // Gate before writing, so a pause takes effect at a clean
            // chunk boundary and never splits a chunk across the pause.
            await _waitWhilePaused();
            if (_cancelled) {
              onStatus?.call('Transfer cancelled.');
              socket.destroy();
              return false;
            }

            socket.add(chunk);
            bytesSent += chunk.length;

            // Let the socket drain before queueing more. Without this,
            // a fast disk feeding a slow link buffers the whole file in
            // memory, and a "pause" would only stop the disk read while
            // megabytes of already-buffered data kept flowing out.
            //
            // Batching these flushes into a larger window was tried as a
            // throughput fix and measured no better: three loopback runs
            // of a 500 MB file gave 53.9/48.2/33.3 MB/s per-chunk versus
            // 42.7/40.5/35.4 MB/s per 4 MB window — indistinguishable
            // noise. It makes sense in hindsight: at 4 MB/s a 64 KB chunk
            // spends ~16 ms on the wire and ~0.1 ms coming off a warm
            // disk, so overlapping the two saves under 1%. The link is
            // the bottleneck, not the pipeline. Batching only bought a
            // larger in-flight window for pause to have to discard.
            await socket.flush();

            // Progress drives setState on the GUI, so reporting every
            // chunk means ~60 full rebuilds a second at speed — enough
            // to become the bottleneck itself. Time-throttled instead,
            // with the final byte always reported so the bar lands on
            // 100% rather than stopping just short.
            final now = DateTime.now();
            if (bytesSent >= entry.size ||
                now.difference(lastProgressAt) >= _progressInterval) {
              lastProgressAt = now;
              onProgress?.call(TransferProgress(
                filename: entry.name,
                bytesDone: bytesSent,
                totalBytes: entry.size,
                fileIndex: i + 1,
                fileCount: files.length,
              ));
            }
          }
        } catch (e) {
          onError?.call('Failed reading "${entry.name}" (file ${i + 1} of ${files.length}): $e');
          socket.destroy();
          return false;
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
