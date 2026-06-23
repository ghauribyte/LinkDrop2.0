import 'dart:io';
import 'lib/engine/file_sender.dart';
import 'lib/models/transfer_progress.dart';

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: dart sender.dart <receiver_ip> <receiver_cert.pem> <file_path> [more_file_paths...]');
    exit(1);
  }

  final receiverIp = args[0];
  final certPath = args[1];
  final filePaths = args.sublist(2);

  final sender = FileSender(
    receiverIp: receiverIp,
    filePaths: filePaths,
    receiverCertPath: certPath,
    onStatus: (msg) => print(msg),
    onProgress: (TransferProgress p) {
      final prefix = p.isBatch ? '[${p.batchLabel}] ' : '';
      stdout.write('\r${prefix}Sending ${p.filename} — ${p.doneMB} MB / ${p.totalMB} MB');
    },
    onComplete: () => print('\nTransfer complete (${filePaths.length} file(s)).'),
    onError: (msg) {
      print(msg);
      exit(1);
    },
  );

  final ok = await sender.send();
  if (!ok) exit(1);
}
