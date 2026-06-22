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
    while (_running) {
      try {
        final message = jsonEncode({
          'type': 'announce',
          'name': deviceName,
          'id': deviceId,
        });
        final data = utf8.encode(message);
        _socket!.send(data, InternetAddress('255.255.255.255'), port);
        onStatus?.call('Broadcasting as $deviceName (id: $deviceId)...');
      } catch (e) {
        onError?.call(e);
        break;
      }
      await Future.delayed(interval);
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
