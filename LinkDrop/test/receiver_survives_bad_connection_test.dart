import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/engine/cert_manager.dart';
import 'package:linkdrop/engine/file_receiver.dart';

/// Pins a bug found by accident: probing the transfer port with a plain TCP
/// connection killed the receiver for the rest of the app's life.
///
/// Port 7979 is a TLS server socket, so a connection that never completes a
/// handshake arrives as an *error on the stream*, not as a socket. The accept
/// loop used `await for`, which ends on the first error — so one stray
/// connection (a port scan, a browser at the wrong address, a health check)
/// stopped the receiver accepting anything. The cert server on the next port
/// kept answering, so the device still looked reachable while every send
/// failed with "connection refused".
void main() {
  late Directory scratch;
  late String certPath;
  late String keyPath;
  late FileReceiver receiver;

  // Not 7979: a real app or another test run may hold the default, and this
  // test must not depend on which.
  const port = 7991;
  const certPort = 7992;

  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('linkdrop_badconn_');
    certPath = '${scratch.path}/cert.pem';
    keyPath = '${scratch.path}/key.pem';
    await CertManager.ensureCertExists(certPath: certPath, keyPath: keyPath);
  });

  tearDown(() async {
    receiver.stop();
    // Give the sockets a moment to actually release before the next bind.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('a plain TCP probe does not stop the receiver listening', () async {
    receiver = FileReceiver(
      targetDir: Directory('${scratch.path}/received'),
      certPath: certPath,
      keyPath: keyPath,
      port: port,
      certServerPort: certPort,
    );

    expect(await receiver.start(), isTrue);

    // Exactly what a port scanner does, and what a /dev/tcp probe did by
    // hand: open a plain connection to the TLS port and drop it without
    // speaking TLS.
    final probe = await Socket.connect('127.0.0.1', port);
    await probe.close();
    probe.destroy();

    // Let the handshake failure propagate through the accept loop.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The receiver must still accept connections. Against the old `await for`
    // loop this throws SocketException: Connection refused.
    final after = await Socket.connect('127.0.0.1', port)
        .timeout(const Duration(seconds: 3));
    addTearDown(() => after.destroy());

    expect(after.remotePort, port,
        reason: 'the receiver stopped listening after one bad connection');
  });
}
