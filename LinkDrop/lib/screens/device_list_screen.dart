import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/discovery_broadcaster.dart';
import '../engine/discovery_listener.dart';
import '../models/device.dart';

/// Shows devices found on the local network, live, with no manual
/// refresh needed. Starts broadcasting this device's presence and
/// listening for others as soon as the screen opens; stops both
/// cleanly when the screen closes (same lifecycle as Ctrl+C in the
/// CLI broadcaster.dart / listener.dart).
///
/// Tapping a device returns it to whoever pushed this screen — this
/// is what the next task (send file flow) will use to know which
/// device the user picked.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late final DiscoveryBroadcaster _broadcaster;
  late final DiscoveryListener _listener;

  final Map<String, Device> _devices = {};
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

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

    _listener = DiscoveryListener(
      onDeviceFound: (device) {
        if (!mounted) return;
        // Don't show ourselves — we hear our own broadcast packets
        // since broadcaster and listener run in the same app/machine.
        if (device.id == _broadcaster.deviceId) return;
        setState(() => _devices[device.id] = device);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _errorMessage = 'Listener error: $e');
      },
    );

    _broadcaster.start();
    _listener.start();
  }

  @override
  void dispose() {
    // Same cleanup as Ctrl+C in the CLI scripts — stop both so the
    // ports are released and no background loop keeps running after
    // the user navigates away.
    _broadcaster.stop();
    _listener.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Devices')),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _statusMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: devices.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        leading: const Icon(Icons.devices),
                        title: Text(device.name),
                        subtitle: Text(device.ipAddress),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(device),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_find,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'Looking for devices on your network...',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
