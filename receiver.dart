import 'dart:io';
import 'lib/engine/file_receiver.dart';
import 'lib/models/transfer_progress.dart';

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: dart receiver.dart <target_directory> <cert.pem> <key.pem>');
    exit(1);
  }

  final receiver = FileReceiver(
    targetDir: Directory(args[0]),
    certPath: args[1],
    keyPath: args[2],
    onStatus: (msg) => print(msg),
    onConnection: (ip, port) => print('\nSecure connection from $ip:$port'),
    onProgress: (TransferProgress p) {
      stdout.write('\rReceiving ${p.filename} — ${p.doneMB} MB / ${p.totalMB} MB');
    },
    onComplete: (filename) => print('\nTransfer complete: $filename'),
    onError: (msg) => print('\n$msg'),
  );

  final started = await receiver.start();
  if (!started) exit(1);

  print('Certificate: ${args[1]}');

  ProcessSignal.sigint.watch().listen((signal) async {
    print('\nShutting down server...');
    await receiver.stop();
    exit(0);
  });
}
