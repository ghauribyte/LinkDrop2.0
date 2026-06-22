import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/cert_exchange.dart';
import '../engine/file_sender.dart';
import '../models/device.dart';
import '../models/transfer_progress.dart';
import 'device_list_screen.dart';

enum _SendState { idle, pickingDevice, fetchingCert, sending, done, failed }

/// Orchestrates the full send flow:
/// 1. Pick a file from disk
/// 2. Pick a device from DeviceListScreen
/// 3. Fetch that device's cert automatically (Decision 011 — no more
///    manual cert copying)
/// 4. Hand off to the existing, already-tested FileSender
///
/// This screen does not duplicate any transfer logic — it only wires
/// together engine pieces that already work on their own.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  _SendState _state = _SendState.idle;
  String? _filePath;
  String? _fileName;
  Device? _device;
  String? _errorMessage;
  TransferProgress? _progress;

  Future<void> _pickFileAndSend() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) {
      return; // user cancelled — stay on idle, no error
    }

    setState(() {
      _filePath = result.files.single.path;
      _fileName = result.files.single.name;
      _errorMessage = null;
      _state = _SendState.pickingDevice;
    });

    if (!mounted) return;
    final device = await Navigator.of(context).push<Device>(
      MaterialPageRoute(builder: (_) => const DeviceListScreen()),
    );

    if (device == null) {
      // user backed out of device picker — reset to idle
      setState(() => _state = _SendState.idle);
      return;
    }

    setState(() {
      _device = device;
      _state = _SendState.fetchingCert;
    });

    await _fetchCertAndSend(device);
  }

  Future<void> _fetchCertAndSend(Device device) async {
    final certPem = await fetchCert(ip: device.ipAddress);

    if (!mounted) return;

    if (certPem == null) {
      setState(() {
        _state = _SendState.failed;
        _errorMessage =
            'Could not get ${device.name}\'s certificate. Make sure they have LinkDrop open and you\'re on the same network.';
      });
      return;
    }

    // FileSender expects a cert file path, not raw PEM text — write
    // the fetched cert to a temp file so the existing, already-tested
    // FileSender code doesn't need to change at all.
    final tempDir = await Directory.systemTemp.createTemp('linkdrop_cert_');
    final tempCertFile = File('${tempDir.path}/receiver_cert.pem');
    await tempCertFile.writeAsString(certPem);

    setState(() => _state = _SendState.sending);

    final sender = FileSender(
      receiverIp: device.ipAddress,
      filePath: _filePath!,
      receiverCertPath: tempCertFile.path,
      onProgress: (p) {
        if (!mounted) return;
        setState(() => _progress = p);
      },
      onComplete: () {
        if (!mounted) return;
        setState(() => _state = _SendState.done);
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _state = _SendState.failed;
          _errorMessage = msg;
        });
      },
    );

    await sender.send();

    // Clean up the temp cert file/dir regardless of outcome.
    await tempDir.delete(recursive: true);
  }

  void _reset() {
    setState(() {
      _state = _SendState.idle;
      _filePath = null;
      _fileName = null;
      _device = null;
      _errorMessage = null;
      _progress = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send a File')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _SendState.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.send,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const Text('Pick a file to send to a nearby device.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pickFileAndSend,
              icon: const Icon(Icons.attach_file),
              label: const Text('Choose File'),
            ),
          ],
        );

      case _SendState.pickingDevice:
        return const CircularProgressIndicator();

      case _SendState.fetchingCert:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Connecting to ${_device?.name ?? "device"}...'),
          ],
        );

      case _SendState.sending:
        final p = _progress;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sending $_fileName to ${_device?.name}'),
            const SizedBox(height: 16),
            if (p != null) ...[
              LinearProgressIndicator(value: p.fraction),
              const SizedBox(height: 8),
              Text('${p.doneMB} MB / ${p.totalMB} MB'),
            ] else
              const LinearProgressIndicator(),
          ],
        );

      case _SendState.done:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('$_fileName sent to ${_device?.name}'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _reset,
              child: const Text('Send Another File'),
            ),
          ],
        );

      case _SendState.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _reset,
              child: const Text('Try Again'),
            ),
          ],
        );
    }
  }
}
