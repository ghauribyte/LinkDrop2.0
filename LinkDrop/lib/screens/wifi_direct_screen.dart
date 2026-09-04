import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/wifi_direct_channel.dart';
import '../models/device.dart';
import '../theme/linkdrop_theme.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Wi-Fi Direct peer discovery and connection (Android only).
///
/// Bridges to native WifiP2pManager via MethodChannel/EventChannel. Once a
/// group is formed both devices share a subnet (group owner is typically
/// 192.168.49.1) and the normal transfer engine takes over.
class WifiDirectScreen extends StatefulWidget {
  const WifiDirectScreen({super.key});

  @override
  State<WifiDirectScreen> createState() => _WifiDirectScreenState();
}

class _WifiDirectScreenState extends State<WifiDirectScreen> {
  late final WifiDirectChannel _channel;
  List<P2pPeer> _peers = [];
  String? _status;
  String? _error;
  P2pConnectionInfo? _connection;
  bool _supported = false;
  bool _connecting = false;
  String? _selectedAddress;
  bool _disposed = false;

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _channel = WifiDirectChannel(
      onPeersChanged: (peers) => _safeSetState(() => _peers = peers),
      onConnectionChanged: (info) => _safeSetState(() {
        _connection = info;
        _connecting = false;
        _status = info.isConnected
            ? (info.isGroupOwner
                ? 'Connected — you are the group owner (192.168.49.1). '
                    'Waiting for the other device to connect to you.'
                : 'Connected — group owner is at ${info.groupOwnerAddress}.')
            : 'Disconnected.';
      }),
      onWifiP2pStateChanged: (enabled) => _safeSetState(() =>
          _status = enabled
              ? 'Wi-Fi Direct is on.'
              : 'Wi-Fi Direct is off — enable Wi-Fi.'),
      onError: (e) =>
          _safeSetState(() => _error = 'Wi-Fi Direct error: $e'),
    );
    _init();
  }

  Future<void> _init() async {
    final supported = await _channel.isSupported;
    if (_disposed || !mounted) return;
    _safeSetState(() => _supported = supported);
    if (!supported) {
      _safeSetState(() => _error =
          'Wi-Fi Direct is not supported on this device/platform.');
      return;
    }

    // Android 13+ wants NEARBY_WIFI_DEVICES; older Android needs location.
    // permission_handler's nearbyWifiDevices check is unreliable on some
    // OEM skins (confirmed: Samsung One UI) — request both, but only
    // hard-block on location, since that's the one P2P discovery has
    // always actually relied on under the hood.
    final statuses = await [
      Permission.nearbyWifiDevices,
      Permission.locationWhenInUse,
    ].request();

    final locationStatus = statuses[Permission.locationWhenInUse];
    if (locationStatus == null ||
        locationStatus.isDenied ||
        locationStatus.isPermanentlyDenied) {
      _safeSetState(() => _error =
          'Wi-Fi Direct needs Location permission to find peers.');
      return;
    }

    // nearbyWifiDevices being reported denied is treated as a soft warning
    // only — discovery is attempted regardless, since the OS-level grant
    // (verified via adb dumpsys) can be true even when permission_handler
    // reports it incorrectly on some devices.
    final nearbyStatus = statuses[Permission.nearbyWifiDevices];
    if (nearbyStatus != null &&
        (nearbyStatus.isDenied || nearbyStatus.isPermanentlyDenied)) {
      _safeSetState(() => _status =
          'Nearby Devices permission may need to be granted in system '
          'Settings if no peers appear.');
    }

    _channel.startListening();
    await _channel.startDiscovery();
  }

  Future<void> _connectTo(P2pPeer peer) async {
    _safeSetState(() {
      _connecting = true;
      _selectedAddress = peer.address;
      _error = null;
    });
    final ok = await _channel.connect(peer.address);
    if (!ok) {
      _safeSetState(() {
        _connecting = false;
        _error = 'Could not connect to ${peer.name}.';
      });
    }
  }

  Future<void> _disconnect() async {
    await _channel.disconnect();
    _safeSetState(() {
      _connection = null;
      _selectedAddress = null;
      _status = 'Disconnected.';
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.stopDiscovery();
    _channel.stopListening();
    super.dispose();
  }

  bool get _isConnected => _connection?.isConnected ?? false;

  @override
  Widget build(BuildContext context) {
    return LinkDropShell(
      title: 'Wi-Fi Direct',
      content: _buildContent(context),
      detail: _isConnected ? _buildConnected(context) : null,
      statusLine: _buildStatusLine(context),
      actions: _isConnected
          ? Row(
              children: [
                TextButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Disconnect'),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildContent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (!_supported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off_outlined, size: 34, color: scheme.onSurfaceVariant),
          const SizedBox(height: 18),
          Text('Wi-Fi Direct unavailable',
              style: text.headlineMedium?.copyWith(fontSize: 22)),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Checking Wi-Fi Direct support…',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    if (_isConnected) {
      final info = _connection!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline,
              size: 38, color: context.transferColors.success),
          const SizedBox(height: 18),
          Text('Connected', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            info.isGroupOwner
                ? 'This device is the group owner. The other device connects '
                    'to you — start receiving and wait for them.'
                : 'Group owner is at ${info.groupOwnerAddress}. You can send '
                    'straight to it, no discovery needed.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    if (_peers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          PulseEmptyState(
            icon: Icons.wifi_tethering,
            title: 'Searching for devices…',
            subtitle: 'Open Wi-Fi Direct on the other device so it can be '
                'found.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 22),
            Text(_error!,
                style: text.bodySmall?.copyWith(color: scheme.error)),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Nearby Wi-Fi Direct devices'),
        const SizedBox(height: 12),
        for (final peer in _peers)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DeviceRow(
              name: peer.name,
              subtitle: _connecting && _selectedAddress == peer.address
                  ? 'Connecting…'
                  : peer.address,
              isPhone: true,
              selected: _selectedAddress == peer.address,
              onTap: _connecting ? null : () => _connectTo(peer),
            ),
          ),
      ],
    );
  }

  /// Sends files / receives files directly over the just-established P2P
  /// link, bypassing UDP broadcast discovery entirely — the platform API
  /// already told us the peer's IP (for the non-owner side), and a
  /// receiver just needs to bind, which works over any active interface
  /// regardless of P2P role. This is the actual "private mode" handoff
  /// from Decision 006.
  Widget _buildConnected(BuildContext context) {
    final info = _connection!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final canSendDirectly =
        !info.isGroupOwner && info.groupOwnerAddress.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Direct link'),
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
              Text(
                info.isGroupOwner ? 'Group owner (this device)' : 'Group owner',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(
                info.isGroupOwner
                    ? '192.168.49.1'
                    : info.groupOwnerAddress,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Next'),
        const SizedBox(height: 10),
        if (canSendDirectly)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Send files to peer'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SendScreen(
                    presetDevice: Device(
                      id: 'wifi-direct-owner',
                      name: 'Wi-Fi Direct peer',
                      ipAddress: info.groupOwnerAddress,
                      lastSeen: DateTime.now(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (canSendDirectly) const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Receive files'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReceiveScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildStatusLine(BuildContext context) {
    if (_error != null && !_supported) return null;
    final message = _status;
    if (message == null) return null;

    return StatusLine(
      message: message,
      live: _isConnected || _connecting,
      color: _isConnected
          ? context.transferColors.success
          : Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
