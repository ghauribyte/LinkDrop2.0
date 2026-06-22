import 'dart:io';
import 'lib/engine/file_sender.dart';
import 'lib/models/transfer_progress.dart';

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: dart sender.dart <receiver_ip> <file_path> <receiver_cert.pem>');
    exit(1);
  }

  final sender = FileSender(
    receiverIp: args[0],
    filePath: args[1],
    receiverCertPath: args[2],
    onStatus: (msg) => print(msg),
    onProgress: (TransferProgress p) {
      stdout.write('\rSending ${p.filename} — ${p.doneMB} MB / ${p.totalMB} MB');
    },
    onComplete: () => print('\nTransfer complete.'),
    onError: (msg) {
      print(msg);
      exit(1);
    },
  );

  final ok = await sender.send();
  if (!ok) exit(1);
}
