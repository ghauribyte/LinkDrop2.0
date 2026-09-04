import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/discovery_broadcaster.dart';
import '../engine/discovery_listener.dart';
import '../models/device.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import 'send_screen.dart';

/// Shows devices found on the local network, live, with no manual
/// refresh needed. Starts broadcasting this device's presence and
/// listening for others as soon as the screen opens; stops both
/// cleanly when the screen closes (same lifecycle as Ctrl+C in the
/// CLI broadcaster.dart / listener.dart).
///
/// Selecting a device shows its detail beside the list rather than
/// navigating away — selection is state, not navigation. The device is
/// still returned to whoever pushed this screen when confirmed, so the
/// existing send flow is unchanged.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late final DiscoveryBroadcaster _broadcaster;
  late final DiscoveryListener _listener;

  final Map<String, Device> _devices = {};
  String? _selectedId;
  String? _errorMessage;

  /// Peers announce every 2s. After this long without a packet a device is
  /// treated as gone — otherwise an offline peer stays listed forever and
  /// tapping it produces a confusing "could not get certificate" error.
  /// Generous enough to ride out a couple of dropped UDP broadcasts.
  static const _staleAfter = Duration(seconds: 10);
  Timer? _pruneTimer;

  /// Set at the top of [dispose] so engine callbacks stop touching state.
  /// `mounted` alone is not enough: it is still true for the duration of
  /// dispose(), and DiscoveryBroadcaster.stop() fires onStatus synchronously
  /// from inside it.
  bool _disposed = false;

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();

    _broadcaster = DiscoveryBroadcaster(
      deviceName: Platform.localHostname,
      onStatus: (_) {},
      onError: (e) =>
          _safeSetState(() => _errorMessage = 'Broadcast error: $e'),
    );

    _listener = DiscoveryListener(
      onDeviceFound: (device) {
        if (_disposed || !mounted) return;
        // Don't show ourselves — we hear our own broadcast packets
        // since broadcaster and listener run in the same app/machine.
        if (device.id == _broadcaster.deviceId) return;
        setState(() => _devices[device.id] = device);
      },
      onError: (e) =>
          _safeSetState(() => _errorMessage = 'Listener error: $e'),
    );

    _broadcaster.start();
    _listener.start();

    _pruneTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pruneStaleDevices(),
    );
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    final gone = _devices.entries
        .where((e) => now.difference(e.value.lastSeen) > _staleAfter)
        .map((e) => e.key)
        .toList();
    if (gone.isEmpty) return;

    _safeSetState(() {
      for (final id in gone) {
        _devices.remove(id);
      }
      if (_selectedId != null && !_devices.containsKey(_selectedId)) {
        _selectedId = null;
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pruneTimer?.cancel();
    // Same cleanup as Ctrl+C in the CLI scripts — stop both so the
    // ports are released and no background loop keeps running after
    // the user navigates away.
    _broadcaster.stop();
    _listener.stop();
    super.dispose();
  }

  List<Device> get _sorted {
    final list = _devices.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Device? get _selected =>
      _selectedId == null ? null : _devices[_selectedId];

  String _freshness(Device device) {
    final seconds = DateTime.now().difference(device.lastSeen).inSeconds;
    if (seconds <= 1) return 'seen just now';
    return 'seen ${seconds}s ago';
  }

  void _confirm(Device device) {
    // Returned to whoever pushed this screen — the send flow is unchanged.
    Navigator.of(context).pop(device);
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < Bp.phone;

    return LinkDropShell(
      title: 'Nearby devices',
      // Centred only while the list is empty and we are still looking; the
      // moment a device appears the list takes over and anchors to the top.
      centerContent: _devices.isEmpty,
      content: _buildList(context, isPhone),
      detail: isPhone ? null : _buildDetail(context),
      statusLine: _buildStatusLine(context),
    );
  }

  Widget _buildList(BuildContext context, bool isPhone) {
    final devices = _sorted;
    final scheme = Theme.of(context).colorScheme;

    if (devices.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          PulseEmptyState(
            icon: Icons.wifi_find,
            title: 'Looking for devices…',
            subtitle: 'Keep LinkDrop open on the other device.',
            // Neutral rather than accent: the app is looking for something
            // that may simply not be there.
            color: scheme.onSurfaceVariant,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final device in devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DeviceRow(
              name: device.name,
              subtitle: '${device.ipAddress} · ${_freshness(device)}',
              selected: device.id == _selectedId,
              // On phone there is no detail pane to show, so a tap confirms
              // directly rather than selecting into nothing.
              onTap: () => isPhone
                  ? _confirm(device)
                  : _safeSetState(() => _selectedId = device.id),
            ),
          ),
      ],
    );
  }

  /// Selected-device detail: identity, fingerprint, and the send action.
  Widget _buildDetail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final device = _selected;

    if (device == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('No device selected'),
          const SizedBox(height: 10),
          Text(
            _devices.isEmpty
                ? 'Devices running LinkDrop on this network will appear '
                    'on the left.'
                : 'Pick a device on the left to see its details and send '
                    'to it.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Selected device'),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.laptop_outlined, size: 22, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.headlineMedium?.copyWith(fontSize: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          device.ipAddress,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          _freshness(device),
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        // The peer's fingerprint is only known once its cert has been
        // fetched, which happens at send time — promising it here would be
        // a lie, so this says what will actually happen instead.
        Text(
          'Their certificate is fetched and verified when you send. '
          'Nothing is trusted in advance.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _confirm(device),
            icon: const Icon(Icons.send_outlined, size: 18),
            label: const Text('Send to this device'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SendScreen(presetDevice: device),
              ),
            ),
            child: const Text('Pick files for this device'),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusLine(BuildContext context) {
    final count = _devices.length;
    return StatusLine(
      message: count == 0
          ? 'Scanning this network…'
          : '$count ${count == 1 ? 'device' : 'devices'} seen on this network',
      color: count == 0
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : null,
    );
  }
}
