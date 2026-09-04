import 'dart:io';

import 'lib/engine/cert_exchange.dart';
import 'lib/engine/file_sender.dart';

/// Throughput benchmark against a running LinkDrop receiver.
///
/// Exists because the GUI's on-screen rate is smoothed and hard to read off
/// reliably, and because comparing LinkDrop to another tool needs both
/// measured the same way on the same link.
///
/// Waits for the receiver's cert port to answer before starting, so the
/// receiver can be opened on the phone without racing this script — leaving
/// the Receive screen tears the listener down, and a fixed sleep here would
/// just move the race rather than remove it.
///
///   dart bench_send.dart <receiver_ip> <file>
void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart bench_send.dart <receiver_ip> <file>');
    exit(1);
  }

  final ip = args[0];
  final path = args[1];
  final file = File(path);
  if (!file.existsSync()) {
    print('No such file: $path');
    exit(1);
  }

  final totalBytes = file.lengthSync();
  final mb = totalBytes / (1024 * 1024);
  print('File: $path (${mb.toStringAsFixed(1)} MiB)');

  print('Waiting for receiver at $ip:7980 ...');
  String? cert;
  for (var attempt = 0; attempt < 900; attempt++) {
    cert = await fetchCert(ip: ip, port: 7980);
    if (cert != null) break;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  if (cert == null) {
    print('Receiver never answered. Is the Receive screen open on the phone?');
    exit(1);
  }

  final certFile = File('${Directory.systemTemp.path}/linkdrop_bench_cert.pem');
  await certFile.writeAsString(cert);
  print('Got cert (${cert.length} chars)');

  final sender = FileSender(
    receiverIp: ip,
    filePaths: [path],
    receiverCertPath: certFile.path,
    onError: (m) => print('ERROR: $m'),
  );

  print('Sending...');
  final started = DateTime.now();
  final ok = await sender.send();
  final elapsed = DateTime.now().difference(started);

  if (!ok) {
    print('Transfer failed after ${elapsed.inSeconds}s');
    exit(1);
  }

  final seconds = elapsed.inMilliseconds / 1000.0;
  final rate = mb / seconds;
  print('');
  print('=== ${mb.toStringAsFixed(1)} MiB in ${seconds.toStringAsFixed(1)}s '
      '= ${rate.toStringAsFixed(1)} MiB/s ===');
}
