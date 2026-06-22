import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: dart receiver.dart <target_directory> <cert.pem> <key.pem>');
    exit(1);
  }

  final targetDir = Directory(args[0]);
  final certPath = args[1];
  final keyPath = args[2];

  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  // Verify cert and key files exist before binding
  if (!await File(certPath).exists()) {
    print('Error: Certificate file not found: $certPath');
    exit(1);
  }
  if (!await File(keyPath).exists()) {
    print('Error: Key file not found: $keyPath');
    exit(1);
  }

  final context = SecurityContext()
    ..useCertificateChain(certPath)
    ..usePrivateKey(keyPath);

  final serverSocket = await SecureServerSocket.bind(
    InternetAddress.anyIPv4,
    7979,
    context,
  );

  print('Secure receiver listening on port 7979 (TLS)');
  print('Certificate: $certPath');

  ProcessSignal.sigint.watch().listen((ProcessSignal signal) async {
    print('\nShutting down server...');
    await serverSocket.close();
    exit(0);
  });

  await for (SecureSocket socket in serverSocket) {
    print('\nSecure connection from ${socket.remoteAddress.address}:${socket.remotePort}');
    await handleConnection(socket, targetDir);
  }
}

void printProgress(String filename, int received, int total) {
  final receivedMB = (received / (1024 * 1024)).toStringAsFixed(2);
  final totalMB = (total / (1024 * 1024)).toStringAsFixed(2);
  stdout.write('\rReceiving $filename — $receivedMB MB / $totalMB MB');
}

Future<void> handleConnection(SecureSocket socket, Directory targetDir) async {
  try {
    final bytesBuilder = BytesBuilder();
    int? headerLength;
    Map<String, dynamic>? header;
    IOSink? fileSink;
    String? filename;
    int? totalSize;
    int fileBytesReceived = 0;
    bool headerParsed = false;

    await for (final data in socket) {
      if (!headerParsed) {
        bytesBuilder.add(data);

        if (headerLength == null && bytesBuilder.length >= 4) {
          final buffer = bytesBuilder.takeBytes();
          final byteData = ByteData.sublistView(Uint8List.fromList(buffer.sublist(0, 4)));
          headerLength = byteData.getUint32(0, Endian.big);
          bytesBuilder.add(buffer.sublist(4));
        }

        if (headerLength != null && bytesBuilder.length >= headerLength!) {
          final buffer = bytesBuilder.takeBytes();
          final jsonBytes = buffer.sublist(0, headerLength!);
          final jsonStr = utf8.decode(jsonBytes);
          header = jsonDecode(jsonStr);
          filename = header!['filename'];
          totalSize = header['size'];

          final file = File('${targetDir.path}/$filename');
          fileSink = file.openWrite();
          headerParsed = true;

          final remaining = buffer.sublist(headerLength!);
          if (remaining.isNotEmpty) {
            fileSink.add(remaining);
            fileBytesReceived += remaining.length;
            printProgress(filename!, fileBytesReceived, totalSize!);
          }
        }
      } else {
        fileSink!.add(data);
        fileBytesReceived += data.length;
        printProgress(filename!, fileBytesReceived, totalSize!);
      }
    }

    if (fileSink != null) {
      await fileSink.flush();
      await fileSink.close();
      print('\nTransfer complete: $filename');
    }
  } catch (e) {
    print('\nError during transfer: $e');
  } finally {
    socket.destroy();
  }
}
