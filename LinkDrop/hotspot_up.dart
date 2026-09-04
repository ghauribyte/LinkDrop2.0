// Throwaway harness: brings up the LinkDrop hotspot via the app's own
// HotspotManager and prints the credentials, so the phone can join.
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
