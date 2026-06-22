import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main() async {
  final port = 6868;
  
  // Generate a random id
  final random = Random();
  final id = List.generate(6, (_) => random.nextInt(16).toRadixString(16)).join();
  final name = Platform.localHostname;

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;

  print('Starting broadcaster...');

  // Handle Ctrl+C cleanly
  ProcessSignal.sigint.watch().listen((signal) {
    print('\nStopping broadcaster...');
    socket.close();
    exit(0);
  });

  while (true) {
    final message = jsonEncode({
      'type': 'announce',
      'name': name,
      'id': id,
    });

    final data = utf8.encode(message);
    socket.send(data, InternetAddress('255.255.255.255'), port);

    print('Broadcasting as $name (id: $id)...');
    await Future.delayed(Duration(seconds: 2));
  }
}
