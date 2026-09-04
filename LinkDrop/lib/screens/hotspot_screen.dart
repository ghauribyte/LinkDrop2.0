import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../engine/hotspot_manager.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import 'receive_screen.dart';
import 'send_screen.dart';
import 'wifi_direct_screen.dart';

/// Lets a Linux device share a direct subnet with a phone — without
/// both being on the same router Wi-Fi.
///
/// Flow:
///   1. Linux app opens this screen → nmcli creates a hotspot named
///      "LinkDrop" with a fresh random password.
///   2. A Wi-Fi QR code is shown on screen.
///   3. Android user points their camera at the QR (works on Android 10+
///      — no third-party scanner needed).
///   4. Phone joins the hotspot. Both devices are now on the same subnet
///      (typically 10.42.0.x). Discovery, send, receive — everything
///      works normally from here: DiscoveryBroadcaster already sends to
///      every interface's directed broadcast address rather than picking
///      one, precisely so the hotspot's subnet isn't left out.
///
/// Hosting is a desktop capability: on Android the phone is the joiner, so
/// this screen says so plainly rather than offering something that cannot
/// work there.
///
/// Send and Receive are reachable from *this* screen via [Navigator.push]
/// rather than the rail: switching rail destinations disposes whatever
/// screen is left, and this one tears the hotspot down in [dispose]. Pushing
/// keeps it mounted underneath, so going to send or receive doesn't kill the
/// connection that was just set up. [JoinHotspotScreen] already does the
/// same thing on the joining side.
class HotspotScreen extends StatefulWidget {
  const HotspotScreen({super.key, this.autoStart = true});

  /// Whether to bring the hotspot up as soon as the screen appears.
  ///
  /// Always true in the app — hosting is the entire point of opening this
  /// screen. It exists so the layout can be rendered in a test without
  /// `nmcli` reconfiguring the host's Wi-Fi as a side effect of taking a
  /// screenshot.
  final bool autoStart;

  @override
  State<HotspotScreen> createState() => _HotspotScreenState();
}

class _HotspotScreenState extends State<HotspotScreen> {
  late final HotspotManager _manager;

  HotspotInfo? _info;
  String? _status;
  String? _error;
  bool _loading = true;
  bool _disposed = false;

  /// True once a hotspot has actually been brought up, so dispose only tears
  /// down something that exists.
  bool _started = false;

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _manager = HotspotManager(
      onStatus: (msg) => _safeSetState(() => _status = msg),
      onError: (msg) => _safeSetState(() {
        _error = msg;
        _loading = false;
      }),
    );
    if (Platform.isLinux && widget.autoStart) {
      _start();
    } else if (!widget.autoStart) {
      _loading = false;
    }
  }

  Future<void> _start() async {
    _started = true;
    _safeSetState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    final info = await _manager.start();
    if (_disposed || !mounted) return;

    _safeSetState(() {
      _info = info;
      _loading = false;
      if (info == null && _error == null) {
        _error = 'Could not create hotspot. Make sure nmcli is installed '
            'and you have permission to create a Wi-Fi hotspot.';
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    // Only tear down what we brought up. stop() shells out to nmcli, so
    // calling it unconditionally would touch the host's network even on a
    // screen that never started a hotspot.
    if (_started) _manager.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinkDropShell(
      title: 'Host a hotspot',
      content: _buildContent(context),
      detail: Platform.isLinux && _info != null ? _buildQrHero(context) : null,
      detailWidth: 420,
      statusLine: _buildStatusLine(context),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // Hosting belongs to the desktop build — say so instead of failing.
    if (!Platform.isLinux) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.smartphone_outlined,
              size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 18),
          Text('Hotspot hosting is a desktop screen',
              style: text.headlineMedium?.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            'This mode belongs to the Linux build. On Android the phone '
            'joins a hotspot through the system Wi-Fi sheet, or uses '
            'Wi-Fi Direct.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const WifiDirectScreen()),
            ),
            icon: const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Use Wi-Fi Direct'),
          ),
        ],
      );
    }

    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          PulseEmptyState(
            icon: Icons.qr_code_2,
            title: 'Starting hotspot…',
            subtitle: _status ?? 'Asking NetworkManager for a Wi-Fi hotspot.',
          ),
        ],
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 38, color: scheme.error),
          const SizedBox(height: 18),
          Text('Could not host a hotspot', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    // Not loading, no error, and nothing to show: the hotspot has not been
    // started. Previously this fell through to `_info!` and threw a null
    // check — an unreachable state today, but a crash waiting for the first
    // path that stops loading without recording an error.
    final info = _info;
    if (info == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.qr_code_2, size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 18),
          Text('Hotspot not started', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'This laptop can broadcast its own Wi-Fi so the phone can join '
            'directly — no router needed.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('Start hotspot'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Host a hotspot', style: text.headlineMedium),
        const SizedBox(height: 10),
        Text(
          'This laptop is broadcasting its own Wi-Fi. Scan the code with '
          'the phone to join — no router, no internet needed.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 26),
        const _Step(1, 'Open LinkDrop on the phone'),
        const _Step(2, 'Tap Join hotspot and scan this code'),
        const _Step(3, 'Send or receive as usual'),
        const SizedBox(height: 24),
        _Credentials(info: info),
      ],
    );
  }

  /// The QR is the hero of this screen, and it sits on a deliberately light
  /// panel: scanners want maximum contrast, and a dark-on-dark QR is
  /// noticeably slower to acquire.
  Widget _buildQrHero(BuildContext context) {
    final info = _info!;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(
              data: info.wifiQrString,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
              // Explicit dark-on-white regardless of app theme.
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${info.ssid} · scan to join',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget? _buildActions(BuildContext context) {
    if (!Platform.isLinux || _loading) return null;

    final hasHotspot = _info != null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        // Pushed on top of this screen rather than reached via the rail:
        // switching rail destinations disposes whatever screen is left, and
        // this one tears the hotspot down in dispose(). Pushing keeps
        // HotspotScreen mounted underneath, so the connection the user just
        // set up survives the trip to send or receive.
        if (hasHotspot) ...[
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SendScreen()),
            ),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('Send files'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReceiveScreen()),
            ),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Receive files'),
          ),
        ],
        OutlinedButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(_error == null ? 'New password' : 'Try again'),
        ),
      ],
    );
  }

  Widget? _buildStatusLine(BuildContext context) {
    if (!Platform.isLinux) return null;
    final info = _info;
    if (info == null) return null;
    return StatusLine(
      message: info.ipAddress == null
          ? 'Hotspot up — waiting for the phone to join'
          : 'Hotspot up on ${info.ipAddress} — waiting for the phone to join',
    );
  }
}

/// A numbered instruction, accent circle plus text.
class _Step extends StatelessWidget {
  const _Step(this.number, this.label);

  final int number;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: TextStyle(fontSize: 11, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// SSID / password / gateway, in monospace so they can be typed accurately
/// by anyone whose camera will not scan the code.
class _Credentials extends StatelessWidget {
  const _Credentials({required this.info});

  final HotspotInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Credentials'),
          const SizedBox(height: 12),
          _Row(label: 'SSID', value: info.ssid),
          _Row(label: 'Password', value: info.password),
          if (info.ipAddress != null)
            _Row(label: 'Gateway', value: info.ipAddress!),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          SelectableText(
            value,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Home-screen entry point, kept for callers that still use it.
/// Renders nothing off Linux.
class HotspotEntryPoint extends StatelessWidget {
  const HotspotEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const HotspotScreen()),
      ),
      icon: const Icon(Icons.qr_code_2),
      label: const Text('Host hotspot · QR'),
    );
  }
}
