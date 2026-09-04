import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/navigation/rail_scope.dart';
import 'package:linkdrop/screens/device_list_screen.dart';
import 'package:linkdrop/screens/home_screen.dart';
import 'package:linkdrop/screens/join_hotspot_screen.dart';
import 'package:linkdrop/screens/receive_screen.dart';
import 'package:linkdrop/screens/send_screen.dart';
import 'package:linkdrop/theme/linkdrop_theme.dart';

/// Renders screens at the two canvases the design was drawn on
/// (Linux 1280dp, Android 412dp) so layout and alignment can be inspected
/// as images rather than guessed at.
///
/// Run with:  flutter test test/ui_golden_test.dart --update-goldens
/// The PNGs land in test/goldens/.
///
/// These verify *layout*, not typography: the test environment has no Inter,
/// so every glyph renders as a filled box. Ignore text shapes; look at
/// alignment, spacing, and where boxes start and end.
///
/// `HotspotScreen` is deliberately absent. Its initState calls
/// `HotspotManager.start()`, which shells out to `nmcli` and creates a real
/// hotspot on the host — rendering it in a test would reconfigure the
/// developer's Wi-Fi. Check that screen by running the app.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // Screens ask path_provider where to save incoming files. The plugin has no
  // implementation under `flutter test`, so answer with a scratch directory —
  // nothing is actually written during a render.
  setUp(() {
    final scratch = Directory.systemTemp
        .createTempSync('linkdrop_golden_')
      ..createSync(recursive: true);
    addTearDown(() {
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
    });

    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => scratch.path,
    );
  });

  Future<void> pumpAt(
    WidgetTester tester, {
    required Size size,
    required Widget child,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RailScope(
        destinations: railDestinations(),
        currentIndex: 0,
        onSelect: (_) {},
        child: MaterialApp(
          theme: linkDropDarkTheme,
          home: child,
        ),
      ),
    );
    // Let the pulse animations settle to a fixed frame.
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Screens that open sockets keep a repeating announce/prune timer alive.
  /// Pumping past the interval lets those fire and settle so the test does
  /// not end with a pending-timer failure.
  Future<void> settleTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
  }

  const desktop = Size(1280, 800);
  const phone = Size(412, 892);

  testWidgets('home · desktop', (tester) async {
    await pumpAt(tester, size: desktop, child: const HomeScreen());
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_desktop.png'),
    );
  });

  testWidgets('home · phone', (tester) async {
    await pumpAt(tester, size: phone, child: const HomeScreen());
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_phone.png'),
    );
  });

  testWidgets('send · desktop', (tester) async {
    await pumpAt(tester, size: desktop, child: const SendScreen());
    await expectLater(
      find.byType(SendScreen),
      matchesGoldenFile('goldens/send_desktop.png'),
    );
  });

  testWidgets('send · phone', (tester) async {
    await pumpAt(tester, size: phone, child: const SendScreen());
    await expectLater(
      find.byType(SendScreen),
      matchesGoldenFile('goldens/send_phone.png'),
    );
  });

  testWidgets('receive · desktop', (tester) async {
    await pumpAt(tester, size: desktop, child: const ReceiveScreen());
    await expectLater(
      find.byType(ReceiveScreen),
      matchesGoldenFile('goldens/receive_desktop.png'),
    );
    await settleTimers(tester);
  });

  testWidgets('receive · phone', (tester) async {
    await pumpAt(tester, size: phone, child: const ReceiveScreen());
    await expectLater(
      find.byType(ReceiveScreen),
      matchesGoldenFile('goldens/receive_phone.png'),
    );
    await settleTimers(tester);
  });

  testWidgets('nearby · desktop', (tester) async {
    await pumpAt(tester, size: desktop, child: const DeviceListScreen());
    await expectLater(
      find.byType(DeviceListScreen),
      matchesGoldenFile('goldens/nearby_desktop.png'),
    );
    await settleTimers(tester);
  });

  testWidgets('nearby · phone', (tester) async {
    await pumpAt(tester, size: phone, child: const DeviceListScreen());
    await expectLater(
      find.byType(DeviceListScreen),
      matchesGoldenFile('goldens/nearby_phone.png'),
    );
    await settleTimers(tester);
  });

  testWidgets('join hotspot · desktop', (tester) async {
    await pumpAt(tester, size: desktop, child: const JoinHotspotScreen());
    await expectLater(
      find.byType(JoinHotspotScreen),
      matchesGoldenFile('goldens/join_hotspot_desktop.png'),
    );
  });
}
