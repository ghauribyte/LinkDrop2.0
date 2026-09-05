import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/about_screen.dart';
import '../screens/device_list_screen.dart';
import '../screens/home_screen.dart';
import '../screens/hotspot_screen.dart';
import '../screens/join_hotspot_screen.dart';
import '../screens/receive_screen.dart';
import '../screens/received_files_screen.dart';
import '../screens/send_screen.dart';
import '../screens/wifi_direct_screen.dart';

/// A rail destination. Platform-gated screens are absent from the list
/// rather than present-and-disabled: Wi-Fi Direct does not exist on Linux,
/// and hotspot hosting does not exist on Android.
class RailDestination {
  const RailDestination({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

/// The destinations available on this platform, in rail order.
List<RailDestination> railDestinations() {
  return [
    RailDestination(
      icon: Icons.home_outlined,
      label: 'Home',
      builder: (_) => const HomeScreen(),
    ),
    RailDestination(
      icon: Icons.send_outlined,
      label: 'Send',
      builder: (_) => const SendScreen(),
    ),
    RailDestination(
      icon: Icons.download_outlined,
      label: 'Receive',
      builder: (_) => const ReceiveScreen(),
    ),
    RailDestination(
      icon: Icons.folder_open_outlined,
      label: 'Received',
      builder: (_) => const ReceivedFilesScreen(),
    ),
    RailDestination(
      icon: Icons.devices_outlined,
      label: 'Nearby',
      builder: (_) => const DeviceListScreen(),
    ),
    if (Platform.isAndroid)
      RailDestination(
        icon: Icons.wifi_tethering,
        label: 'Wi-Fi Direct',
        builder: (_) => const WifiDirectScreen(),
      ),
    if (Platform.isLinux) ...[
      RailDestination(
        icon: Icons.qr_code_2,
        label: 'QR hotspot',
        builder: (_) => const HotspotScreen(),
      ),
      RailDestination(
        icon: Icons.wifi,
        label: 'Join hotspot',
        builder: (_) => const JoinHotspotScreen(),
      ),
    ],
    // Last on both platforms: version and the update check are the thing you
    // go looking for, not something you pass through.
    RailDestination(
      icon: Icons.info_outline,
      label: 'About',
      builder: (_) => const AboutScreen(),
    ),
  ];
}

/// Carries rail state down to every screen, including pushed routes.
///
/// Installed above the app's Navigator (via `MaterialApp.builder`) so a
/// screen pushed on top of a destination — the device picker, for instance —
/// still sees the rail and can navigate from it.
class RailScope extends InheritedWidget {
  const RailScope({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required super.child,
  });

  final List<RailDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  static RailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RailScope>();

  @override
  bool updateShouldNotify(RailScope oldWidget) =>
      oldWidget.currentIndex != currentIndex ||
      oldWidget.destinations.length != destinations.length;
}
