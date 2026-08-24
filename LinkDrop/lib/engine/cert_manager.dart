import 'dart:io';

import 'package:basic_utils/basic_utils.dart';

/// Generates and caches a self-signed ECDSA (P-256) certificate + key
/// pair entirely in Dart — no `openssl`/shell required (Decision 015).
///
/// Needed because Android has no shell access, so the manual `openssl`
/// workflow (docs/TODO.md Phase 3) only ever worked on desktop.
class CertManager {
  /// Ensures [certPath]/[keyPath] both exist, generating a new
  /// self-signed pair on first call. A no-op if both files are already
  /// present, so the same identity/fingerprint persists across launches.
  static Future<void> ensureCertExists({
    required String certPath,
    required String keyPath,
  }) async {
    final certFile = File(certPath);
    final keyFile = File(keyPath);

    if (await certFile.exists() && await keyFile.exists()) {
      return;
    }

    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final privateKey = pair.privateKey as ECPrivateKey;
    final publicKey = pair.publicKey as ECPublicKey;

    final csrPem = X509Utils.generateEccCsrPem(
      {'CN': 'linkdrop'},
      privateKey,
      publicKey,
    );

    // 10-year validity: this is a self-signed, fingerprint-verified
    // identity (Decision 003/011), not a CA-issued cert with a renewal
    // flow — the expiry date itself isn't part of the trust model.
    final certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csrPem,
      3650,
    );

    final keyPem = CryptoUtils.encodeEcPrivateKeyToPem(privateKey);

    await certFile.parent.create(recursive: true);
    await certFile.writeAsString(certPem);
    await keyFile.writeAsString(keyPem);
  }
}
