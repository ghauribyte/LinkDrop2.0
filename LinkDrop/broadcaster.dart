import 'dart:io';
import 'lib/engine/discovery_broadcaster.dart';

void main() async {
  final broadcaster = DiscoveryBroadcaster(
    deviceName: Platform.localHostname,
    onStatus: (msg) => print(msg),
    onError: (e) {
      print('Error: $e');
      exit(1);
    },
  );

  await broadcaster.start();

  ProcessSignal.sigint.watch().listen((signal) {
    broadcaster.stop();
    exit(0);
  });
}
