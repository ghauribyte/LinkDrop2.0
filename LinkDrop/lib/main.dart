import 'package:flutter/material.dart';

import 'navigation/rail_scope.dart';
import 'screens/home_screen.dart';
import 'theme/linkdrop_theme.dart';
import 'widgets/linkdrop_shell.dart';

void main() {
  runApp(const LinkDropApp());
}

class LinkDropApp extends StatefulWidget {
  const LinkDropApp({super.key});

  @override
  State<LinkDropApp> createState() => _LinkDropAppState();
}

class _LinkDropAppState extends State<LinkDropApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  int _railIndex = 0;

  /// Switching destinations returns to the root route first, so the rail
  /// selection always matches what is actually on screen.
  ///
  /// Only the selected destination is built, so leaving a screen disposes it
  /// — the same lifecycle as backing out of a pushed route today. That keeps
  /// the receiver's sockets and the discovery broadcaster from starting on
  /// launch, at the cost of not being able to wander off mid-transfer.
  void _selectDestination(int index) {
    if (index == _railIndex) return;
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _railIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = railDestinations();
    final index = _railIndex.clamp(0, destinations.length - 1);

    return MaterialApp(
      title: 'LinkDrop',
      navigatorKey: _navigatorKey,
      // Dark is the design's default mode. Light is a full peer rather than a
      // tint and stays wired, so switching to ThemeMode.system is a one-line
      // change whenever the light scheme has been reviewed.
      theme: linkDropLightTheme,
      darkTheme: linkDropDarkTheme,
      themeMode: ThemeMode.dark,
      // Installed above the Navigator so pushed routes see the rail too.
      builder: (context, child) => RailScope(
        destinations: destinations,
        currentIndex: index,
        onSelect: _selectDestination,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _RootDestination(),
    );
  }
}

/// Renders the rail's current destination on desktop.
///
/// Below the phone breakpoint there is no rail, so Home is always the root
/// and everything else is reached by pushing — which is what gives the phone
/// its back-arrow header.
class _RootDestination extends StatelessWidget {
  const _RootDestination();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < Bp.phone) {
      return const HomeScreen();
    }

    final rail = RailScope.maybeOf(context);
    if (rail == null || rail.destinations.isEmpty) return const HomeScreen();

    final index = rail.currentIndex.clamp(0, rail.destinations.length - 1);
    return rail.destinations[index].builder(context);
  }
}
