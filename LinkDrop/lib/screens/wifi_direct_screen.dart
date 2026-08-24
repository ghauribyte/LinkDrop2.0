import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/wifi_direct_channel.dart';
import '../models/device.dart';
import 'receive_screen.dart';
import 'send_screen.dart';

/// Discovers nearby Wi-Fi Direct peers and connects to one.
/// On success, forms a P2P group — one device becomes the group owner
/// (acts like a small router, IP typically 192.168.49.1), the other
/// gets a P2P-assigned IP on the same virtual subnet.
///
/// Returns the IP to actually connect FileSender/FileReceiver to:
/// - If we are the group owner: the *peer's* IP is needed, but P2P
///   doesn't expose the peer's IP directly — only ours and whether
///   we're the owner. In practice, the non-owner side initiates the
///   TCP connection to 192.168.49.1 (the owner's fixed address); the
///   owner side runs FileReceiver bound to all interfaces as usual.
/// - If we are NOT the group owner: groupOwnerAddress IS the IP to
///   connect to directly.
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

  @override
  void initState() {
    super.initState();
    _channel = WifiDirectChannel(
      onPeersChanged: (peers) {
        if (!mounted) return;
        setState(() => _peers = peers);
      },
      onConnectionChanged: (info) {
        if (!mounted) return;
        setState(() {
          _connection = info;
          _connecting = false;
          _status = info.isConnected
              ? (info.isGroupOwner
                  ? 'Connected — you are the group owner (192.168.49.1). Waiting for the other device to connect to you.'
                  : 'Connected — group owner is at ${info.groupOwnerAddress}. Use this IP to send/receive.')
              : 'Disconnected.';
        });
      },
      onWifiP2pStateChanged: (enabled) {
        if (!mounted) return;
        setState(() => _status = enabled ? 'Wi-Fi Direct is on.' : 'Wi-Fi Direct is off — enable Wi-Fi.');
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _error = 'Wi-Fi Direct error: $e');
      },
    );
    _init();
  }

  Future<void> _init() async {
    final supported = await _channel.isSupported;
    if (!mounted) return;
    setState(() => _supported = supported);
    if (!supported) {
      setState(() => _error = 'Wi-Fi Direct is not supported on this device/platform.');
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
    if (locationStatus == null || locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
      if (!mounted) return;
      setState(() => _error = 'Wi-Fi Direct needs Location permission to find peers.');
      return;
    }

    // nearbyWifiDevices being reported denied is treated as a soft warning
    // only — discovery is attempted regardless, since the OS-level grant
    // (verified via adb dumpsys) can be true even when permission_handler
    // reports it incorrectly on some devices.
    final nearbyStatus = statuses[Permission.nearbyWifiDevices];
    if (nearbyStatus != null && (nearbyStatus.isDenied || nearbyStatus.isPermanentlyDenied)) {
      setState(() => _status = 'Nearby Devices permission may need to be granted in system Settings if no peers appear.');
    }

    _channel.startListening();
    await _channel.startDiscovery();
  }

  Future<void> _connectTo(P2pPeer peer) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final ok = await _channel.connect(peer.address);
    if (!ok && mounted) {
      setState(() {
        _connecting = false;
        _error = 'Could not connect to ${peer.name}.';
      });
    }
  }

  Future<void> _disconnect() async {
    await _channel.disconnect();
    if (!mounted) return;
    setState(() {
      _connection = null;
      _status = 'Disconnected.';
    });
  }

  @override
  void dispose() {
    _channel.stopDiscovery();
    _channel.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wi-Fi Direct')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(context),
      ),
    );
  }

  /// Sends files / receives files directly over the just-established P2P
  /// link, bypassing UDP broadcast discovery entirely — the platform API
  /// already told us the peer's IP (for the non-owner side), and a
  /// receiver just needs to bind, which works over any active interface
  /// regardless of P2P role. This is the actual "private mode" handoff
  /// from Decision 006: once a direct connection exists, use it straight
  /// away instead of requiring discovery to also work over that link.
  Widget _buildTransferActions(BuildContext context, P2pConnectionInfo info) {
    final canSendDirectly = !info.isGroupOwner && info.groupOwnerAddress.isNotEmpty;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (canSendDirectly)
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send Files to Peer'),
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
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Receive Files'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ReceiveScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_supported) {
      return Center(
        child: Text(_error ?? 'Checking Wi-Fi Direct support...'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Text(_error!),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_status!, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (_connection?.isConnected == true) ...[
          _buildTransferActions(context, _connection!),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _disconnect, child: const Text('Disconnect')),
        ],
        const SizedBox(height: 8),
        const Text('Nearby Wi-Fi Direct devices:'),
        Expanded(
          child: _peers.isEmpty
              ? const Center(child: Text('Searching for devices...'))
              : ListView.builder(
                  itemCount: _peers.length,
                  itemBuilder: (context, i) {
                    final peer = _peers[i];
                    return ListTile(
                      leading: const Icon(Icons.wifi_tethering),
                      title: Text(peer.name),
                      subtitle: Text(peer.address),
                      trailing: _connecting
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator())
                          : const Icon(Icons.chevron_right),
                      onTap: _connecting ? null : () => _connectTo(peer),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
