import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/hotspot_manager.dart';
import '../theme/linkdrop_theme.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Joins a hotspot hosted by another machine — the other half of
/// [HotspotScreen], for Linux-to-Linux transfers where the receiving
/// machine has no camera to scan a QR code with and must type the SSID
/// and password instead.
///
/// This is the app's only real form screen, so it gets a proper measure
/// rather than stretching across the window.
class JoinHotspotScreen extends StatefulWidget {
  const JoinHotspotScreen({super.key});

  @override
  State<JoinHotspotScreen> createState() => _JoinHotspotScreenState();
}

class _JoinHotspotScreenState extends State<JoinHotspotScreen> {
  late final HotspotManager _manager;

  // Defaults to the SSID HotspotManager.start() always creates, so in
  // the normal case the user only has to type the password.
  final _ssidController = TextEditingController(text: 'LinkDrop');
  final _passwordController = TextEditingController();

  String? _status;
  String? _error;
  String? _joinedIp;
  String? _joinedSsid;
  bool _joining = false;
  bool _obscurePassword = true;
  bool _disposed = false;

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
        _joining = false;
      }),
    );
  }

  Future<void> _join() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;

    _safeSetState(() {
      _joining = true;
      _error = null;
      _joinedIp = null;
    });

    final ip = await _manager.join(ssid: ssid, password: password);
    if (_disposed || !mounted) return;

    _safeSetState(() {
      _joining = false;
      if (ip != null) {
        _joinedIp = ip;
        _joinedSsid = ssid;
      }
      // A null IP with no _error set means join() returned without
      // reporting why — surface something rather than failing silently.
      if (ip == null && _error == null) {
        _error = 'Could not join "$ssid". Check the password and make sure '
            'the other machine\'s hotspot is still running.';
      }
    });
  }

  Future<void> _leave() async {
    final ssid = _joinedSsid;
    if (ssid == null) return;
    await _manager.leave(ssid);
    _safeSetState(() {
      _joinedIp = null;
      _joinedSsid = null;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinkDropShell(
      title: 'Join a hotspot',
      content: ConstrainedBox(
        // The form gets a real measure — a full-width text field on a
        // 1600dp monitor is unreadable, not generous.
        constraints: const BoxConstraints(maxWidth: 560),
        child: _buildContent(context),
      ),
      detail: _joinedIp == null ? null : _buildConnected(context),
      statusLine: _buildStatusLine(context),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (!Platform.isLinux) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi, size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 18),
          Text('Join from system Wi-Fi',
              style: text.headlineMedium?.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            'On Android, join the host\'s hotspot from the system Wi-Fi '
            'settings — scanning the QR code on the hosting machine does '
            'this for you.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    if (_joinedIp != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline,
              size: 38, color: context.transferColors.success),
          const SizedBox(height: 18),
          Text('Joined $_joinedSsid', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Both machines are on the same subnet now. Send and receive '
            'work as usual.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Join a hotspot', style: text.headlineMedium),
        const SizedBox(height: 10),
        Text(
          'Type the SSID and password shown on the hosting machine. No '
          'router or internet is involved.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 26),
        const SectionLabel('Network'),
        const SizedBox(height: 12),
        TextField(
          controller: _ssidController,
          enabled: !_joining,
          decoration: const InputDecoration(
            labelText: 'SSID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          enabled: !_joining,
          obscureText: _obscurePassword,
          onSubmitted: (_) => _joining ? null : _join(),
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
              ),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () =>
                  _safeSetState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 17, color: scheme.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Once connected, the second pane carries where to go next.
  Widget _buildConnected(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('This device'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('On $_joinedSsid', style: text.bodyMedium),
              const SizedBox(height: 4),
              SelectableText(
                _joinedIp!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Next'),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SendScreen()),
            ),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('Send files'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReceiveScreen()),
            ),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Receive files'),
          ),
        ),
      ],
    );
  }

  Widget? _buildActions(BuildContext context) {
    if (!Platform.isLinux) return null;

    if (_joinedIp != null) {
      return Row(
        children: [
          TextButton.icon(
            onPressed: _leave,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Disconnect'),
          ),
        ],
      );
    }

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _joining ? null : _join,
          icon: const Icon(Icons.wifi, size: 18),
          label: Text(_joining ? 'Joining…' : 'Join hotspot'),
        ),
      ],
    );
  }

  Widget? _buildStatusLine(BuildContext context) {
    if (!Platform.isLinux) return null;

    if (_joining) {
      return StatusLine(
        message: _status ?? 'Asking NetworkManager to join…',
        color: Theme.of(context).colorScheme.primary,
      );
    }
    if (_joinedIp != null) {
      return StatusLine(message: 'Connected on $_joinedIp');
    }
    // Joining a hotspot drops the current Wi-Fi — a warning, not an error.
    return StatusLine(
      message: 'Joining a hotspot will disconnect this machine from its '
          'current Wi-Fi',
      live: false,
      color: context.transferColors.warning,
    );
  }
}

/// Home-screen entry point, kept for callers that still use it.
/// Renders nothing off Linux.
class JoinHotspotEntryPoint extends StatelessWidget {
  const JoinHotspotEntryPoint({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isLinux) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const JoinHotspotScreen()),
      ),
      icon: const Icon(Icons.wifi),
      label: const Text('Join a hotspot'),
    );
  }
}
