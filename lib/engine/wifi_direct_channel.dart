import 'dart:async';
import 'package:flutter/services.dart';

/// A discovered Wi-Fi Direct peer device.
class P2pPeer {
  final String name;
  final String address;
  final int status;

  P2pPeer({required this.name, required this.address, required this.status});

  factory P2pPeer.fromMap(Map<dynamic, dynamic> m) => P2pPeer(
        name: m['name'] as String,
        address: m['address'] as String,
        status: m['status'] as int,
      );
}

/// Wi-Fi Direct connection state — emitted when a P2P group forms/breaks.
class P2pConnectionInfo {
  final bool isConnected;
  final bool isGroupOwner;
  final String groupOwnerAddress;

  P2pConnectionInfo({
    required this.isConnected,
    required this.isGroupOwner,
    required this.groupOwnerAddress,
  });
}

/// Dart-side bridge to the native Android WifiP2pManager implementation
/// in MainActivity.kt (Decision 015 — Wi-Fi Direct via platform channel).
/// Android-only. Callers must check [isSupported] before using this —
/// it always returns false/no-ops on non-Android platforms.
class WifiDirectChannel {
  static const _method = MethodChannel('linkdrop/wifi_direct');
  static const _events = EventChannel('linkdrop/wifi_direct_events');

  final void Function(List<P2pPeer> peers)? onPeersChanged;
  final void Function(P2pConnectionInfo info)? onConnectionChanged;
  final void Function(bool enabled)? onWifiP2pStateChanged;
  final void Function(Object error)? onError;

  StreamSubscription? _sub;

  WifiDirectChannel({
    this.onPeersChanged,
    this.onConnectionChanged,
    this.onWifiP2pStateChanged,
    this.onError,
  });

  Future<bool> get isSupported async {
    try {
      final result = await _method.invokeMethod<bool>('isSupported');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  void startListening() {
    _sub = _events.receiveBroadcastStream().listen(
      (event) {
        final map = event as Map<dynamic, dynamic>;
        switch (map['type']) {
          case 'peers':
            final peers = (map['peers'] as List)
                .map((p) => P2pPeer.fromMap(p as Map<dynamic, dynamic>))
                .toList();
            onPeersChanged?.call(peers);
            break;
          case 'connection':
            onConnectionChanged?.call(P2pConnectionInfo(
              isConnected: map['isConnected'] as bool,
              isGroupOwner: map['isGroupOwner'] as bool,
              groupOwnerAddress: map['groupOwnerAddress'] as String,
            ));
            break;
          case 'state':
            onWifiP2pStateChanged?.call(map['enabled'] as bool);
            break;
        }
      },
      onError: (e) => onError?.call(e),
    );
  }

  void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  Future<bool> startDiscovery() async {
    try {
      return await _method.invokeMethod<bool>('startDiscovery') ?? false;
    } catch (e) {
      onError?.call(e);
      return false;
    }
  }

  Future<bool> stopDiscovery() async {
    try {
      return await _method.invokeMethod<bool>('stopDiscovery') ?? false;
    } catch (e) {
      onError?.call(e);
      return false;
    }
  }

  /// Requests a P2P connection to [address] (a peer's deviceAddress, as
  /// seen in onPeersChanged). On success, one device becomes the group
  /// owner (acts like a small router, typically 192.168.49.1) — listen
  /// to onConnectionChanged for the resulting groupOwnerAddress.
  Future<bool> connect(String address) async {
    try {
      return await _method.invokeMethod<bool>('connect', {'address': address}) ?? false;
    } catch (e) {
      onError?.call(e);
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      return await _method.invokeMethod<bool>('disconnect') ?? false;
    } catch (e) {
      onError?.call(e);
      return false;
    }
  }
}
