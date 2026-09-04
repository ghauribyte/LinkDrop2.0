// Throwaway harness: a cancel issued *while paused* must release the
// parked send loop rather than deadlocking it.
import 'dart:io';
import 'dart:math';

import 'lib/engine/cert_manager.dart';
import 'lib/engine/file_receiver.dart';
import 'lib/engine/file_sender.dart';

void main() async {
  final tmp = Directory.systemTemp.createTempSync('linkdrop_cancel_');
  final certPath = '${tmp.path}/cert.pem';
  final keyPath = '${tmp.path}/key.pem';
  final outDir = Directory('${tmp.path}/received')..createSync();

  await CertManager.ensureCertExists(certPath: certPath, keyPath: keyPath);

  final src = File('${tmp.path}/big.bin');
  final rng = Random(7);
  final sink = src.openWrite();
  for (var i = 0; i < 24; i++) {
    sink.add(List<int>.generate(1024 * 1024, (_) => rng.nextInt(256)));
  }
  await sink.flush();
  await sink.close();

  final receiver = FileReceiver(
    targetDir: outDir,
    certPath: certPath,
    keyPath: keyPath,
    onIncomingRequest: (files, ip) async => true,
    onRejected: (m) => print('  [recv rejected] $m'),
  );
  await receiver.start();

  final sender = FileSender(
    receiverIp: '127.0.0.1',
    filePaths: [src.path],
    receiverCertPath: certPath,
    onStatus: (m) {
      if (m.contains('cancel')) print('  [status] $m');
    },
  );

  final sendFuture = sender.send();
  await Future.delayed(const Duration(milliseconds: 700));

  sender.pause();
  print('paused');
  await Future.delayed(const Duration(milliseconds: 500));

  print('cancelling while paused...');
  sender.cancel();

  // The whole point: this must return promptly, not hang forever.
  bool timedOut = false;
  final result = await sendFuture.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      timedOut = true;
      return false;
    },
  );

  print(timedOut
      ? 'FAIL: send() hung after cancel-while-paused (deadlock)'
      : 'PASS: send() returned $result promptly after cancel');

  await receiver.stop();
  await Future.delayed(const Duration(milliseconds: 500));

  // Receiver must not leave a half-written file behind (Decision 014).
  final leftovers = outDir.listSync().map((e) => e.path.split('/').last).toList();
  final clean = leftovers.isEmpty;
  print(clean
      ? 'PASS: no partial file left behind after cancel'
      : 'FAIL: partial file(s) left: $leftovers');

  tmp.deleteSync(recursive: true);
  exit(!timedOut && clean ? 0 : 1);
}
