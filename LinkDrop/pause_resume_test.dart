// Throwaway harness: proves pause actually halts the byte flow and
// resume finishes the transfer with a byte-identical result.
//
// stdout is its entire user interface, so avoid_print is noise here rather
// than a finding. Kept file-local so `lib/` stays covered.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

import 'lib/engine/cert_manager.dart';
import 'lib/engine/file_receiver.dart';
import 'lib/engine/file_sender.dart';

void main() async {
  final tmp = Directory.systemTemp.createTempSync('linkdrop_pr_');
  final certPath = '${tmp.path}/cert.pem';
  final keyPath = '${tmp.path}/key.pem';
  final outDir = Directory('${tmp.path}/received')..createSync();

  await CertManager.ensureCertExists(certPath: certPath, keyPath: keyPath);

  // ~24 MB of random data so the transfer lasts long enough to pause.
  final src = File('${tmp.path}/big.bin');
  final rng = Random(42);
  final sink = src.openWrite();
  for (var i = 0; i < 24; i++) {
    sink.add(List<int>.generate(1024 * 1024, (_) => rng.nextInt(256)));
  }
  await sink.flush();
  await sink.close();
  final srcDigest = sha256.convert(await src.readAsBytes()).toString();
  print('source: ${await src.length()} bytes, sha256=${srcDigest.substring(0, 16)}...');

  final receiver = FileReceiver(
    targetDir: outDir,
    certPath: certPath,
    keyPath: keyPath,
    onIncomingRequest: (files, ip) async => true,
    onError: (m) => print('  [recv error] $m'),
    onRejected: (m) => print('  [recv rejected] $m'),
  );
  if (!await receiver.start()) {
    print('FAIL: receiver did not start');
    exit(1);
  }

  int lastBytes = 0;
  final sender = FileSender(
    receiverIp: '127.0.0.1',
    filePaths: [src.path],
    receiverCertPath: certPath,
    onProgress: (p) => lastBytes = p.bytesDone,
    onPausedChanged: (p) => print('  [paused=$p]'),
    onError: (m) => print('  [send error] $m'),
  );

  final sendFuture = sender.send();

  // Let it get going, then pause.
  await Future.delayed(const Duration(milliseconds: 700));
  sender.pause();
  final atPause = lastBytes;
  print('paused at $atPause bytes');

  // While paused, progress must not advance.
  await Future.delayed(const Duration(seconds: 2));
  final afterWait = lastBytes;
  print('after 2s paused: $afterWait bytes');

  final heldStill = afterWait == atPause;
  print(heldStill
      ? 'PASS: transfer stayed frozen while paused'
      : 'FAIL: $atPause -> $afterWait bytes moved while paused');

  sender.resume();
  final ok = await sendFuture;
  print('send() returned $ok, final bytes=$lastBytes');

  await receiver.stop();
  await Future.delayed(const Duration(milliseconds: 300));

  final got = File('${outDir.path}/big.bin');
  if (!got.existsSync()) {
    print('FAIL: no received file');
    exit(1);
  }
  final gotDigest = sha256.convert(await got.readAsBytes()).toString();
  final identical = gotDigest == srcDigest;
  print(identical
      ? 'PASS: received file is byte-identical after pause/resume'
      : 'FAIL: checksum mismatch');

  tmp.deleteSync(recursive: true);
  exit(heldStill && identical && ok ? 0 : 1);
}
