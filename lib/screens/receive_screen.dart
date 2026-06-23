import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/discovery_broadcaster.dart';
import '../engine/file_receiver.dart';
import '../models/manifest_entry.dart';
import '../models/transfer_progress.dart';

/// Runs the receiving side of LinkDrop as a real device:
/// - Broadcasts this device's presence (closes the gap where
///   receiver.dart never broadcast on its own — see TASK_BOARD.md)
/// - Listens for incoming files via FileReceiver
/// - Shows an accept/reject popup before any file is written to disk
/// - Shows live progress once a transfer is accepted
///
/// Needs a cert.pem + key.pem to already exist. For now this screen
/// expects them at <app documents dir>/linkdrop/cert.pem and key.pem —
/// generating/pairing certs automatically is a future task, not yet
/// built. See TODO.md Phase 3 for how to generate them with openssl.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  DiscoveryBroadcaster? _broadcaster;
  FileReceiver? _receiver;

  String? _statusMessage;
  String? _errorMessage;
  TransferProgress? _progress;
  String? _currentFilename;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final linkdropDir = Directory('${docsDir.path}/linkdrop');
    final certPath = '${linkdropDir.path}/cert.pem';
    final keyPath = '${linkdropDir.path}/key.pem';

    if (!await File(certPath).exists() || !await File(keyPath).exists()) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No certificate found at $certPath.\nGenerate one with openssl first (see TODO.md Phase 3), then restart this screen.';
      });
      return;
    }

    _broadcaster = DiscoveryBroadcaster(
      deviceName: Platform.localHostname,
      onStatus: (msg) {
        if (!mounted) return;
        setState(() => _statusMessage = msg);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _errorMessage = 'Broadcast error: $e');
      },
    );

    _receiver = FileReceiver(
      targetDir: Directory('${linkdropDir.path}/received'),
      certPath: certPath,
      keyPath: keyPath,
      onStatus: (msg) {
        if (!mounted) return;
        setState(() => _statusMessage = msg);
      },
      onIncomingRequest: (files, senderIp) =>
          _showAcceptRejectDialog(files, senderIp),
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _currentFilename = p.filename;
        });
      },
      onComplete: (filename) {
        if (!mounted) return;
        setState(() => _statusMessage = 'Received: $filename');
      },
      onBatchComplete: (count) {
        if (!mounted) return;
        setState(() {
          _statusMessage = count == 1
              ? 'Transfer complete.'
              : 'Transfer complete ($count files).';
          _progress = null;
          _currentFilename = null;
        });
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _statusMessage = msg);
      },
    );

    await _broadcaster!.start();
    await _receiver!.start();
  }

  /// Shows the accept/reject popup for the whole incoming batch. The
  /// returned Future resolves when the user taps a button — FileReceiver
  /// awaits this before writing any bytes to disk (see onIncomingRequest
  /// in file_receiver.dart). One decision covers every file in the batch.
  Future<bool> _showAcceptRejectDialog(
    List<ManifestEntry> files,
    String senderIp,
  ) async {
    if (!mounted) return false;

    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);
    final totalMB = (totalBytes / (1024 * 1024)).toStringAsFixed(2);

    final title = files.length == 1 ? 'Incoming File' : 'Incoming Files';
    final fileList = files.length <= 5
        ? files.map((f) => f.name).join('\n')
        : '${files.take(5).map((f) => f.name).join('\n')}\n...and ${files.length - 5} more';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          '$fileList\n\n${files.length} file(s), $totalMB MB total\nfrom $senderIp',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    return result ?? false; // dialog dismissed some other way = reject
  }

  @override
  void dispose() {
    _broadcaster?.stop();
    _receiver?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive Files')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(_errorMessage!, textAlign: TextAlign.center),
        ],
      );
    }

    if (_progress != null) {
      final p = _progress!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Receiving $_currentFilename'),
          if (p.isBatch) ...[
            const SizedBox(height: 4),
            Text(
              'File ${p.batchLabel}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          LinearProgressIndicator(value: p.fraction),
          const SizedBox(height: 8),
          Text('${p.doneMB} MB / ${p.totalMB} MB'),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_tethering,
            size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        const Text('Waiting for incoming files...'),
        if (_statusMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _statusMessage!,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
