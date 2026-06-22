import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart receiver.dart <target_directory>');
    exit(1);
  }

  final targetDir = Directory(args[0]);
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 7979);
  print('Listening on ${serverSocket.address.address}:${serverSocket.port}');

  ProcessSignal.sigint.watch().listen((ProcessSignal signal) async {
    print('\nShutting down server...');
    await serverSocket.close();
    exit(0);
  });

  await for (Socket socket in serverSocket) {
    print('\nConnection from ${socket.remoteAddress.address}:${socket.remotePort}');
    await handleConnection(socket, targetDir);
  }
}

void printProgress(String filename, int received, int total) {
  final receivedMB = (received / (1024 * 1024)).toStringAsFixed(2);
  final totalMB = (total / (1024 * 1024)).toStringAsFixed(2);
  stdout.write('\rReceiving $filename — $receivedMB MB / $totalMB MB');
}

Future<void> handleConnection(Socket socket, Directory targetDir) async {
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
          bytesBuilder.add(buffer.sublist(4)); // put remainder back
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
