import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../engine/wifi_direct_channel.dart';

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

    // Android 13+ requires NEARBY_WIFI_DEVICES at runtime; older Android
    // requires location permission for P2P peer discovery to return results.
    final statuses = await [
      Permission.nearbyWifiDevices,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied) {
      if (!mounted) return;
      setState(() => _error = 'Wi-Fi Direct needs the Nearby Devices / Location permission to find peers.');
      return;
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
        if (_connection?.isConnected == true)
          FilledButton(onPressed: _disconnect, child: const Text('Disconnect')),
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
