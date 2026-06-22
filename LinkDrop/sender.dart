import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart sender.dart <receiver_ip> <file_path>');
    exit(1);
  }

  final receiverIp = args[0];
  final filePath = args[1];
  final file = File(filePath);

  if (!await file.exists()) {
    print('Error: File "$filePath" does not exist.');
    exit(1);
  }

  final filename = file.uri.pathSegments.last;
  final totalSize = await file.length();

  print('Connecting to $receiverIp:7979...');
  late Socket socket;
  try {
    socket = await Socket.connect(receiverIp, 7979);
  } catch (e) {
    print('Error connecting to $receiverIp: $e');
    exit(1);
  }

  final headerMap = {
    'filename': filename,
    'size': totalSize,
  };
  final headerJson = jsonEncode(headerMap);
  final headerBytes = utf8.encode(headerJson);

  final lengthByteData = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);
  socket.add(lengthByteData.buffer.asUint8List());
  socket.add(headerBytes);

  int bytesSent = 0;
  final fileStream = file.openRead();
  
  await for (final chunk in fileStream) {
    socket.add(chunk);
    bytesSent += chunk.length;
    final sentMB = (bytesSent / (1024 * 1024)).toStringAsFixed(2);
    final totalMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);
    stdout.write('\rSending $filename — $sentMB MB / $totalMB MB');
  }

  await socket.flush();
  await socket.close();
  print('\nTransfer complete: $filename');
}
