import 'dart:io';
import 'dart:math';

/// Result of attempting to create/read a hotspot.
class HotspotInfo {
  final String ssid;
  final String password;
  final String? ipAddress; // this device's IP on the hotspot subnet

  HotspotInfo({
    required this.ssid,
    required this.password,
    this.ipAddress,
  });

  /// Standard Wi-Fi QR code string — scannable by Android camera app
  /// (Settings → scan, or just point camera at it on Android 10+).
  /// Format: WIFI:T:WPA;S:<ssid>;P:<password>;;
  String get wifiQrString => 'WIFI:T:WPA;S:${_escape(ssid)};P:${_escape(password)};;';

  /// Escapes special chars in WIFI QR strings per the spec.
  String _escape(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('"', '\\"');
}

/// Manages a Wi-Fi hotspot on Linux via nmcli.
/// On other platforms, all methods return null/false — callers should
/// check [isSupported] before showing this feature in the UI.
class HotspotManager {
  final void Function(String message)? onStatus;
  final void Function(String message)? onError;

  HotspotManager({this.onStatus, this.onError});

  /// True only on Linux — that's the only platform where we drive the
  /// hotspot ourselves. Android is the joining side; it uses the OS
  /// Wi-Fi QR scanner to connect, not this class.
  static bool get isSupported => Platform.isLinux;

  static const _connectionName = 'linkdrop-hotspot';

  /// Creates (or re-uses) a LinkDrop hotspot via nmcli, returning the
  /// SSID, password, and this device's IP on the hotspot subnet.
  ///
  /// Uses a fixed SSID + random password each time the app launches so
  /// the QR code shown is always valid for the current session. The
  /// nmcli connection is named 'linkdrop-hotspot' and is deleted and
  /// recreated each time to avoid stale passwords from a previous run.
  Future<HotspotInfo?> start() async {
    if (!isSupported) return null;

    final ssid = 'LinkDrop';
    final password = _randomPassword();

    onStatus?.call('Creating hotspot "$ssid"...');

    // Delete any previous linkdrop-hotspot connection to avoid conflicts.
    await Process.run('nmcli', [
      'connection', 'delete', _connectionName,
    ]);

    // Create and bring up the hotspot.
    final createResult = await Process.run('nmcli', [
      'device', 'wifi', 'hotspot',
      'con-name', _connectionName,
      'ssid', ssid,
      'password', password,
    ]);

    if (createResult.exitCode != 0) {
      final err = (createResult.stderr as String).trim();
      onError?.call('Failed to create hotspot: $err');
      return null;
    }

    onStatus?.call('Hotspot "$ssid" is active. Waiting for the phone to join...');

    final ip = await _getHotspotIp();
    return HotspotInfo(ssid: ssid, password: password, ipAddress: ip);
  }

  /// Tears down the hotspot by deleting the nmcli connection.
  Future<void> stop() async {
    if (!isSupported) return;
    await Process.run('nmcli', ['connection', 'delete', _connectionName]);
    onStatus?.call('Hotspot stopped.');
  }

  /// Returns this device's IP on the hotspot subnet (typically
  /// 10.42.0.1 when nmcli creates the hotspot). Polls the nmcli
  /// connection details — may take a second or two to appear.
  Future<String?> _getHotspotIp() async {
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final result = await Process.run('nmcli', [
        '-g', 'IP4.ADDRESS',
        'connection', 'show', _connectionName,
      ]);
      final out = (result.stdout as String).trim();
      if (out.isNotEmpty) {
        // nmcli returns "10.42.0.1/24" — strip the prefix length.
        return out.split('/').first;
      }
    }
    return null;
  }

  String _randomPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789'; // no ambiguous chars
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
