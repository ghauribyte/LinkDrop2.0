// Throwaway harness: brings up the LinkDrop hotspot via the app's own
// HotspotManager and prints the credentials, so the phone can join.
//
// stdout is its entire user interface, so avoid_print is noise here rather
// than a finding. Kept file-local so `lib/` stays covered.
// ignore_for_file: avoid_print
import 'lib/engine/hotspot_manager.dart';

void main() async {
  final m = HotspotManager(
    onStatus: (s) => print('[status] $s'),
    onError: (e) => print('[ERROR] $e'),
  );
  final info = await m.start();
  if (info == null) {
    print('FAILED to start hotspot');
    return;
  }
  print('SSID=${info.ssid}');
  print('PASSWORD=${info.password}');
  print('IP=${info.ipAddress}');
}
