import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Broadcasts this device's presence on the local network via UDP.
/// Same wire format and timing as the original broadcaster.dart —
/// only the input/output style changed (callbacks instead of print/exit)
/// so this can be driven by a CLI script or a Flutter UI.
class DiscoveryBroadcaster {
  final String deviceId;
  final String deviceName;
  final int port;
  final Duration interval;

  /// Called whenever the broadcaster wants to report status.
  /// CLI wrapper can print this; Flutter can show it in the UI.
  final void Function(String message)? onStatus;

  /// Called if broadcasting fails to start or hits an unrecoverable error.
  final void Function(Object error)? onError;

  RawDatagramSocket? _socket;
  bool _running = false;

  DiscoveryBroadcaster({
    String? deviceId,
    required this.deviceName,
    this.port = 6868,
    this.interval = const Duration(seconds: 2),
    this.onStatus,
    this.onError,
  }) : deviceId = deviceId ?? _generateId();

  static String _generateId() {
    final random = Random();
    return List.generate(6, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  bool get isRunning => _running;

  /// Starts broadcasting. Does not block — runs the announce loop
  /// in the background. Call [stop] to end it.
  Future<void> start() async {
    if (_running) return;

    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
    } catch (e) {
      onError?.call(e);
      return;
    }

    _running = true;
    onStatus?.call('Starting broadcaster...');
    _announceLoop();
  }

  void _announceLoop() async {
    var failures = 0;

    while (_running) {
      try {
        final message = jsonEncode({
          'type': 'announce',
          'name': deviceName,
          'id': deviceId,
        });
        final data = utf8.encode(message);

        var sent = 0;
        for (final target in await _broadcastTargets()) {
          try {
            _socket!.send(data, target, port);
            sent++;
          } catch (_) {
            // One dead interface shouldn't stop the others.
          }
        }
        if (sent == 0) {
          throw const SocketException('no reachable broadcast address');
        }

        if (failures > 0) {
          failures = 0;
          onStatus?.call('Broadcasting resumed.');
        }
        onStatus?.call('Broadcasting as $deviceName (id: $deviceId)...');
      } catch (e) {
        // Keep going. Network errors here are routinely transient: bringing a
        // hotspot up drops the interface's address and default route for a
        // moment, and a send() in that window throws. Giving up would leave
        // the device permanently undiscoverable long after the network came
        // back — with _running still true, start() would refuse to restart it.
        failures++;
        if (failures == 1) onError?.call(e); // report once, not every 2s
        await _rebindSocket();
      }
      await Future.delayed(interval);
    }
  }

  /// Every address worth announcing to.
  ///
  /// 255.255.255.255 alone is not enough: it leaves the host on whichever
  /// single interface the routing table picks, so a laptop hosting a hotspot
  /// while still associated to a normal network can broadcast to entirely the
  /// wrong subnet and stay invisible to the phone that just joined it.
  /// Sending to each interface's directed broadcast as well covers that.
  ///
  /// Dart's NetworkInterface does not expose the netmask, so the directed
  /// address assumes a /24. That holds for the setups LinkDrop targets
  /// (nmcli hotspots are 10.42.0.0/24, Wi-Fi Direct 192.168.49.0/24, and
  /// typical home LANs are /24). A wrong guess costs one ignored packet.
  Future<List<InternetAddress>> _broadcastTargets() async {
    final targets = <InternetAddress>[InternetAddress('255.255.255.255')];

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final octets = address.address.split('.');
          if (octets.length != 4) continue;
          targets.add(
            InternetAddress('${octets[0]}.${octets[1]}.${octets[2]}.255'),
          );
        }
      }
    } catch (_) {
      // Enumeration failed — the limited broadcast above still stands a chance.
    }

    return targets;
  }

  /// Replaces the socket after a send failure. An interface that went down and
  /// came back (hotspot toggling) can leave the old socket bound to an address
  /// that no longer exists, in which case every later send keeps failing.
  Future<void> _rebindSocket() async {
    try {
      _socket?.close();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
    } catch (_) {
      // Leave it for the next tick to retry.
    }
  }

  /// Stops broadcasting and releases the socket.
  void stop() {
    _running = false;
    _socket?.close();
    _socket = null;
    onStatus?.call('Stopping broadcaster...');
  }
}
