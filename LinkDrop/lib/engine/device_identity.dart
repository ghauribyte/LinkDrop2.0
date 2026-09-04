import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Who this machine is on the network: the name peers see, the address they
/// reach it on, and the certificate fingerprint they verify it by.
///
/// The Home and Nearby screens show this so a user can compare fingerprints
/// across two devices before accepting a transfer — which is the whole of the
/// trust model (Decision 003), and only works if the value is actually
/// visible somewhere.
class DeviceIdentity {
  const DeviceIdentity({
    required this.name,
    required this.ipAddress,
    this.fingerprint,
  });

  final String name;

  /// Best-guess LAN address, or null if no non-loopback IPv4 was found.
  final String? ipAddress;

  /// SHA-256 of the DER cert as `aa:bb:cc:…`, or null if no cert exists yet.
  final String? fingerprint;

  /// A short, human-comparable form — the first six bytes, upper case.
  /// Comparing 32 bytes by eye is theatre; comparing six is a real check.
  String? get shortFingerprint {
    final full = fingerprint;
    if (full == null) return null;
    final parts = full.split(':');
    return parts.take(6).join(':').toUpperCase();
  }

  /// Gathers identity without throwing: any part that cannot be determined
  /// comes back null rather than failing the whole call, matching the
  /// engine's "report, don't throw" contract (Decision 008).
  static Future<DeviceIdentity> resolve({String? certPath}) async {
    String name;
    try {
      name = Platform.localHostname;
    } catch (_) {
      name = 'this device';
    }

    return DeviceIdentity(
      name: name,
      ipAddress: await localIpAddress(),
      fingerprint:
          certPath == null ? null : await certFingerprint(certPath),
    );
  }

  /// First non-loopback IPv4 address. Prefers a private LAN range, since a
  /// VPN or carrier interface is rarely the one a peer can reach.
  static Future<String?> localIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      String? fallback;
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
          fallback ??= ip;
        }
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  /// SHA-256 fingerprint of a PEM certificate, formatted `aa:bb:cc:…`.
  /// Returns null if the file is missing or unparseable.
  static Future<String?> certFingerprint(String certPath) async {
    try {
      final file = File(certPath);
      if (!await file.exists()) return null;

      final pem = utf8.decode(await file.readAsBytes());
      final body = pem
          .replaceAll('-----BEGIN CERTIFICATE-----', '')
          .replaceAll('-----END CERTIFICATE-----', '')
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .trim();

      final digest = sha256.convert(base64Decode(body));
      return digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':');
    } catch (_) {
      return null;
    }
  }
}
