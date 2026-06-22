import 'dart:convert';
import 'dart:io';

import '../models/device.dart';

/// Listens for UDP announce packets from other devices on the network.
/// Same de-dupe logic as the original listener.dart (10 second window)
/// — only the input/output style changed (callbacks instead of print)
/// so this can be driven by a CLI script or a Flutter UI.
class DiscoveryListener {
  final int port;
  final Duration dedupeWindow;

  /// Called when a new device is found, or an already-seen device
  /// is heard from again after the dedupe window has passed.
  final void Function(Device device)? onDeviceFound;

  /// Called if the listener fails to bind or hits an unrecoverable error.
  final void Function(Object error)? onError;

  RawDatagramSocket? _socket;
  bool _running = false;

  /// id -> last seen time, used for de-duping noisy repeat announcements
  final Map<String, DateTime> _seenDevices = {};

  DiscoveryListener({
    this.port = 6868,
    this.dedupeWindow = const Duration(seconds: 10),
    this.onDeviceFound,
    this.onError,
  });

  bool get isRunning => _running;

  /// Map of all currently known devices, keyed by device id.
  Map<String, Device> get knownDevices => Map.unmodifiable(_knownDevices);
  final Map<String, Device> _knownDevices = {};

  Future<void> start() async {
    if (_running) return;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
    } catch (e) {
      onError?.call(e);
      return;
    }

    _running = true;

    _socket!.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket!.receive();
      if (datagram == null) return;
      _handlePacket(datagram);
    });
  }

  void _handlePacket(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message);

      if (json is Map && json['type'] == 'announce') {
        final id = json['id']?.toString();
        final name = json['name']?.toString();

        if (id != null && name != null) {
          final now = DateTime.now();
          final lastSeen = _seenDevices[id];

          final device = Device(
            id: id,
            name: name,
            ipAddress: datagram.address.address,
            lastSeen: now,
          );

          _knownDevices[id] = device;

          // Report only if new device or hasn't been seen within the window —
          // same de-dupe behavior as the original listener.dart
          if (lastSeen == null || now.difference(lastSeen) >= dedupeWindow) {
            onDeviceFound?.call(device);
          }

          _seenDevices[id] = now;
        }
      }
    } catch (e) {
      // Ignore non-JSON or malformed packets quietly — same as before
    }
  }

  void stop() {
    _running = false;
    _socket?.close();
    _socket = null;
  }
}
