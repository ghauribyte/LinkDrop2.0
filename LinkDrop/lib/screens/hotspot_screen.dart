import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../engine/hotspot_manager.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Lets a Linux device share a direct subnet with a phone — without
/// both being on the same router Wi-Fi.
///
/// Flow:
///   1. Linux app taps "QR Hotspot" → this screen calls nmcli to create
///      a hotspot named "LinkDrop" with a fresh random password.
///   2. A Wi-Fi QR code is shown on screen.
///   3. Android user points their camera at the QR (works on Android 10+
///      — no third-party scanner needed, just the stock camera or
///      Settings → Network → scan QR).
///   4. Phone joins the hotspot. Both devices are now on the same subnet
///      (typically 10.42.0.x). Discovery, send, receive — everything
///      works normally from here.
///
/// Android-side: no code needed. The phone is the joiner, not the host.
/// This screen only runs on Linux.
class HotspotScreen extends StatefulWidget {
  const HotspotScreen({super.key});

  @override
  State<HotspotScreen> createState() => _HotspotScreenState();
}

class _HotspotScreenState extends State<HotspotScreen> {
  late final HotspotManager _manager;

  HotspotInfo? _info;
  String? _status;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _manager = HotspotManager(
      onStatus: (msg) {
        if (!mounted) return;
        setState(() => _status = msg);
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() {
          _error = msg;
          _loading = false;
        });
      },
    );
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    final info = await _manager.start();

    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
      if (info == null && _error == null) {
        _error = 'Could not create hotspot. Make sure nmcli is installed and you have permission to create a Wi-Fi hotspot.';
      }
    });
  }

  @override
  void dispose() {
    _manager.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Hotspot'),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Restart hotspot with a new password',
              onPressed: _start,
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status ?? 'Starting hotspot...'),
        ],
      );
    }

    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      );
    }

    final info = _info!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Scan to join the hotspot',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Point your phone\'s camera at the QR code.\nNo scanner app needed on Android 10+.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),

        // QR code
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: QrImageView(
            data: info.wifiQrString,
            version: QrVersions.auto,
            size: 240,
            backgroundColor: Colors.white,
            errorStateBuilder: (context, error) => const SizedBox(
              width: 240,
              height: 240,
              child: Center(child: Text('QR generation failed')),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Credentials card — useful if camera QR doesn't work
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _credRow(context, 'Network', info.ssid),
                const SizedBox(height: 8),
                _credRow(context, 'Password', info.password),
                if (info.ipAddress != null) ...[
                  const SizedBox(height: 8),
                  _credRow(context, 'This device\'s IP', info.ipAddress!),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Instruction text
        Text(
          'Once the phone has joined, open LinkDrop on the phone\nand use Send / Receive normally.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),

        const SizedBox(height: 16),

        // Quick actions for this device — once the phone has joined the
        // hotspot, both devices are on a normal Wi-Fi subnet, so regular
        // UDP broadcast discovery (DeviceListScreen) works unmodified.
        // These just save backing out to Home to start a transfer.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send Files'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SendScreen()),
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Receive Files'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceiveScreen()),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Status line
        if (_status != null)
          Text(
            _status!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  Widget _credRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(width: 16),
        SelectableText(
          value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ],
    );
  }
}

/// A button/tile for the home screen that only shows on Linux.
/// On other platforms, returns [SizedBox.shrink()].
class HotspotEntryPoint extends StatelessWidget {
  const HotspotEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HotspotScreen()),
      ),
      icon: const Icon(Icons.qr_code),
      label: const Text('QR Hotspot (Linux → Phone)'),
    );
  }
}
