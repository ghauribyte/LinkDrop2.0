import 'dart:convert';
import 'dart:io';

void main() async {
  final port = 6868;
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
  
  print('Starting listener on port $port...');

  // Map to keep track of seen devices: id -> last seen time
  final Map<String, DateTime> seenDevices = {};

  // Handle Ctrl+C cleanly
  ProcessSignal.sigint.watch().listen((signal) {
    print('\nStopping listener...');
    socket.close();
    exit(0);
  });

  socket.listen((RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final datagram = socket.receive();
      if (datagram != null) {
        try {
          final message = utf8.decode(datagram.data);
          final json = jsonDecode(message);
          
          if (json is Map && json['type'] == 'announce') {
            final id = json['id']?.toString();
            final name = json['name']?.toString();
            
            if (id != null && name != null) {
              final now = DateTime.now();
              final lastSeen = seenDevices[id];
              
              // Print only if new device or hasn't been seen in the last ~10 seconds
              if (lastSeen == null || now.difference(lastSeen).inSeconds >= 10) {
                print('Found device: $name (id: $id) at ${datagram.address.address}');
              }
              
              seenDevices[id] = now;
            }
          }
        } catch (e) {
          // Ignore non-JSON or malformed packets quietly
        }
      }
    }
  });
}
