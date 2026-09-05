// Tagged so CI can skip it (`flutter test --exclude-tags golden`). Golden
// images depend on the host's font fallback — see the note below about Inter
// — so a machine that isn't this one produces different pixels for reasons
// that have nothing to do with the layout being verified. These stay a local
// step where the PNGs are actually looked at.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:linkdrop/navigation/rail_scope.dart';
import 'package:linkdrop/screens/about_screen.dart';
import 'package:linkdrop/screens/device_list_screen.dart';
import 'package:linkdrop/screens/home_screen.dart';
import 'package:linkdrop/screens/hotspot_screen.dart';
import 'package:linkdrop/screens/join_hotspot_screen.dart';
import 'package:linkdrop/screens/receive_screen.dart';
import 'package:linkdrop/screens/received_files_screen.dart';
import 'package:linkdrop/screens/send_screen.dart';
import 'package:linkdrop/services/receiver_service.dart';
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
/// `HotspotScreen` is rendered with `autoStart: false`. Its initState
/// otherwise calls `HotspotManager.start()`, which shells out to `nmcli` and
/// creates a real hotspot on the host — a screenshot must never reconfigure
/// the developer's Wi-Fi. Its live QR state still needs a run of the app.
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
    bool light = false,
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
          theme: light ? linkDropLightTheme : linkDropDarkTheme,
          home: child,
        ),
      ),
    );
    // Let the pulse animations settle to a fixed frame.
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Lets a screen's real disk I/O finish before the frame is captured.
  ///
  /// `pumpAndSettle` cannot be used here: it drives a fake clock, so real
  /// file reads never complete under it, and a screen showing a spinner
  /// never settles anyway because the spinner animates forever. runAsync
  /// steps outside the fake clock so the load actually resolves.
  Future<void> settleAsyncLoad(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
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

  // The light scheme is a full peer in the spec, not a tint, but the app
  // pins itself to dark — so without this it would ship having never been
  // looked at. It also puts eyes on the one derived colour in the theme
  // (light outlineVariant), which the spec only supplied for dark.
  testWidgets('home · desktop · light', (tester) async {
    await pumpAt(tester,
        size: desktop, child: const HomeScreen(), light: true);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_desktop_light.png'),
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

  // ReceiveScreen now renders ReceiverService's state, and that service is a
  // process-wide singleton whose start is asynchronous — so without pinning
  // it these goldens would race between "not listening" and "waiting" and
  // change shot to shot. Started explicitly here so the captured frame is
  // always the waiting state, which is the one worth reviewing.
  testWidgets('receive · desktop', (tester) async {
    await tester.runAsync(() => ReceiverService.instance.ensureStarted());
    await pumpAt(tester, size: desktop, child: const ReceiveScreen());
    await expectLater(
      find.byType(ReceiveScreen),
      matchesGoldenFile('goldens/receive_desktop.png'),
    );
    await settleTimers(tester);
  });

  // Deliberately does not stop-and-restart between the two receive goldens:
  // stopping releases ports 7979/7980 and immediately rebinding them from the
  // next test hangs. Started once, torn down after the last one that needs it.
  testWidgets('receive · phone', (tester) async {
    await tester.runAsync(() => ReceiverService.instance.ensureStarted());
    await pumpAt(tester, size: phone, child: const ReceiveScreen());
    await expectLater(
      find.byType(ReceiveScreen),
      matchesGoldenFile('goldens/receive_phone.png'),
    );
    await settleTimers(tester);
    await tester.runAsync(() => ReceiverService.instance.stop());
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

  // Safe now that autoStart is injectable: this renders the screen's shell
  // without nmcli touching the host's Wi-Fi. The live QR state still has to
  // be checked by running the app, since the QR needs a real hotspot.
  testWidgets('host hotspot · desktop', (tester) async {
    await pumpAt(tester,
        size: desktop, child: const HotspotScreen(autoStart: false));
    await expectLater(
      find.byType(HotspotScreen),
      matchesGoldenFile('goldens/host_hotspot_desktop.png'),
    );
  });

  testWidgets('join hotspot · desktop', (tester) async {
    await pumpAt(tester, size: desktop, child: const JoinHotspotScreen());
    await expectLater(
      find.byType(JoinHotspotScreen),
      matchesGoldenFile('goldens/join_hotspot_desktop.png'),
    );
  });

  // Renders the empty state: the log lives in the app documents directory,
  // which the path_provider mock points at a fresh scratch dir per test.
  // pumpAndSettle is needed because the log is read asynchronously — a plain
  // pump captures the loading spinner instead of the state worth checking.
  testWidgets('received files · desktop', (tester) async {
    await pumpAt(tester, size: desktop, child: const ReceivedFilesScreen());
    await settleAsyncLoad(tester);
    await expectLater(
      find.byType(ReceivedFilesScreen),
      matchesGoldenFile('goldens/received_files_desktop.png'),
    );
  });

  testWidgets('received files · phone', (tester) async {
    await pumpAt(tester, size: phone, child: const ReceivedFilesScreen());
    await settleAsyncLoad(tester);
    await expectLater(
      find.byType(ReceivedFilesScreen),
      matchesGoldenFile('goldens/received_files_phone.png'),
    );
  });

  // About reads the installed package's version, which has no plugin under
  // `flutter test` — mocked so these capture the real idle state rather than
  // the "could not read this build's version" error pane.
  //
  // The manifest URL is pointed at an address nothing is listening on. That
  // matters: a golden must never make a network request to github.com as a
  // side effect of being rendered.
  const unreachable = 'http://127.0.0.1:1/latest.json';

  void mockPackageInfo() {
    PackageInfo.setMockInitialValues(
      appName: 'LinkDrop',
      packageName: 'com.linkdrop.linkdrop_app',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  }

  testWidgets('about · desktop', (tester) async {
    mockPackageInfo();
    await pumpAt(
      tester,
      size: desktop,
      child: const AboutScreen(manifestUrl: unreachable),
    );
    await settleAsyncLoad(tester);
    await expectLater(
      find.byType(AboutScreen),
      matchesGoldenFile('goldens/about_desktop.png'),
    );
  });

  testWidgets('about · phone', (tester) async {
    mockPackageInfo();
    await pumpAt(
      tester,
      size: phone,
      child: const AboutScreen(manifestUrl: unreachable),
    );
    await settleAsyncLoad(tester);
    await expectLater(
      find.byType(AboutScreen),
      matchesGoldenFile('goldens/about_phone.png'),
    );
  });

  // The pane the shell rule is really about: idle is one centred subject,
  // but the moment there is a result to read the content anchors to the top
  // and the context pane carries it. A failed check is the state most worth
  // looking at, since it must not resemble "up to date".
  testWidgets('about · desktop · check failed', (tester) async {
    mockPackageInfo();
    await pumpAt(
      tester,
      size: desktop,
      child: const AboutScreen(manifestUrl: unreachable),
    );
    await settleAsyncLoad(tester);

    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await settleAsyncLoad(tester);

    await expectLater(
      find.byType(AboutScreen),
      matchesGoldenFile('goldens/about_desktop_failed.png'),
    );
  });
}
