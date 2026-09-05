// A CLI harness: stdout is its entire user interface, so avoid_print is
// noise here rather than a finding. Kept file-local so `lib/` stays covered.
// ignore_for_file: avoid_print

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
