import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/device_identity.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import 'device_list_screen.dart';
import 'hotspot_screen.dart';
import 'join_hotspot_screen.dart';
import 'receive_screen.dart';
import 'send_screen.dart';
import 'wifi_direct_screen.dart';

/// Entry point. Send and Receive are the product; everything else is a
/// connection mode, needed only when there is no shared network — so the two
/// primary actions are tiles and the modes are a quiet list beside them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DeviceIdentity? _identity;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    String? certPath;
    try {
      final docs = await getApplicationDocumentsDirectory();
      certPath = '${docs.path}/linkdrop/cert.pem';
    } catch (_) {
      // Identity still resolves without a cert — the fingerprint is simply
      // absent until the first receive generates one.
    }

    final identity = await DeviceIdentity.resolve(certPath: certPath);
    if (_disposed || !mounted) return;
    setState(() => _identity = identity);
  }

  void _open(WidgetBuilder builder) {
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < Bp.phone;

    return LinkDropShell(
      title: 'LinkDrop',
      showBackOnPhone: false,
      content: _buildContent(context, isPhone),
      detail: _buildDetail(context),
      statusLine: _buildStatusLine(),
    );
  }

  Widget _buildContent(BuildContext context, bool isPhone) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final tiles = [
      _ActionTile(
        icon: Icons.send_outlined,
        title: 'Send a file',
        subtitle: isPhone
            ? 'Pick files and a device'
            : 'Pick files, pick a device, go.',
        primary: true,
        isPhone: isPhone,
        onTap: () => _open((_) => const SendScreen()),
      ),
      _ActionTile(
        icon: Icons.download_outlined,
        title: 'Receive files',
        subtitle: isPhone
            ? 'Wait for a transfer'
            : 'Listen for an incoming transfer.',
        isPhone: isPhone,
        onTap: () => _open((_) => const ReceiveScreen()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Send anything.\nNowhere else.', style: text.headlineMedium),
        const SizedBox(height: 10),
        Text(
          isPhone
              ? 'Device to device on your own network.'
              : 'Files move directly between the two devices on this '
                  'network. No cloud, no account, no upload.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 26),
        if (isPhone)
          Column(
            children: [
              tiles[0],
              const SizedBox(height: 12),
              tiles[1],
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[0]),
              const SizedBox(width: 16),
              Expanded(child: tiles[1]),
            ],
          ),
        // On phone the connection modes live under the tiles rather than in
        // a side pane, so they still have to appear somewhere.
        if (isPhone) ...[
          const SizedBox(height: 26),
          const SectionLabel('Connection modes'),
          const SizedBox(height: 8),
          ..._connectionModes(context),
        ],
      ],
    );
  }

  /// The context pane: who this device is, then the connection modes.
  /// Null on phone — the content column already carries both.
  Widget? _buildDetail(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < Bp.phone) return null;

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final identity = _identity;

    return SingleChildScrollView(
      child: Column(
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
                Row(
                  children: [
                    Icon(Icons.laptop_outlined,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        identity?.name ?? '…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge?.copyWith(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  identity?.ipAddress ?? 'No network address',
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (identity?.shortFingerprint != null) ...[
                  const SizedBox(height: 12),
                  FingerprintText(identity!.shortFingerprint!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Connection modes'),
          const SizedBox(height: 4),
          Text(
            'Only needed when there is no shared network.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ..._connectionModes(context),
        ],
      ),
    );
  }

  /// Platform-gated: a mode that does not exist here is absent, not disabled.
  List<Widget> _connectionModes(BuildContext context) {
    return [
      _ModeRow(
        icon: Icons.devices_outlined,
        title: 'Nearby devices',
        subtitle: 'Browse this network',
        onTap: () => _open((_) => const DeviceListScreen()),
      ),
      if (Platform.isAndroid)
        _ModeRow(
          icon: Icons.wifi_tethering,
          title: 'Wi-Fi Direct',
          subtitle: 'Connect with no router',
          onTap: () => _open((_) => const WifiDirectScreen()),
        ),
      if (Platform.isLinux) ...[
        _ModeRow(
          icon: Icons.qr_code_2,
          title: 'Host hotspot · QR',
          subtitle: 'Phone scans to join',
          onTap: () => _open((_) => const HotspotScreen()),
        ),
        _ModeRow(
          icon: Icons.wifi,
          title: 'Join a hotspot',
          subtitle: 'Enter SSID and password',
          onTap: () => _open((_) => const JoinHotspotScreen()),
        ),
      ],
    ];
  }

  Widget? _buildStatusLine() {
    final identity = _identity;
    if (identity == null) return null;
    final ip = identity.ipAddress;
    return StatusLine(
      message: ip == null
          ? 'No network address — connect to Wi-Fi or host a hotspot'
          : 'Listening on $ip',
      live: ip != null,
    );
  }
}

/// A primary action tile. The accent is an outline and a tint, never a flood.
///
/// Two shapes for two form factors, not one shape scaled: desktop gets a tall
/// card with the icon at the top and the label anchored to the bottom; phone
/// gets a horizontal row with a chevron, which is what a thumb expects.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isPhone,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPhone;
  final bool primary;

  /// Tall enough that the pair of tiles carries the top of the work pane
  /// rather than floating as two small boxes.
  static const _desktopHeight = 230.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = primary ? scheme.primary : scheme.onSurfaceVariant;

    return Material(
      color: primary ? scheme.primaryContainer : scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: isPhone ? null : _desktopHeight,
          padding: EdgeInsets.all(isPhone ? 16 : 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primary ? scheme.primary : scheme.outlineVariant,
              width: 1,
            ),
          ),
          child: isPhone
              ? Row(
                  children: [
                    Icon(icon, size: 24, color: accent),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              style: text.headlineMedium
                                  ?.copyWith(fontSize: 19)),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: accent),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 26, color: accent),
                    const Spacer(),
                    Text(title,
                        style: text.headlineMedium?.copyWith(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: text.bodyMedium),
                  Text(
                    subtitle,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
