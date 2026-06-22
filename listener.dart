import 'dart:io';
import 'lib/engine/discovery_listener.dart';

void main() async {
  print('Starting listener on port 6868...');

  final listener = DiscoveryListener(
    onDeviceFound: (device) {
      print('Found device: ${device.name} (id: ${device.id}) at ${device.ipAddress}');
    },
    onError: (e) {
      print('Error: $e');
      exit(1);
    },
  );

  await listener.start();

  ProcessSignal.sigint.watch().listen((signal) {
    print('\nStopping listener...');
    listener.stop();
    exit(0);
  });
}
