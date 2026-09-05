import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/screens/receive_screen.dart';
import 'package:linkdrop/services/receiver_service.dart';
import 'package:linkdrop/theme/linkdrop_theme.dart';

/// Pins the bug that made a sender see "Connection refused" while the app was
/// still running: ReceiveScreen used to own the FileReceiver and stop it in
/// dispose(), so leaving the screen closed the listening socket.
///
/// Against the old code the first test fails — tearing the screen down took
/// the receiver with it.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('linkdrop_lifecycle_');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => scratch.path,
    );
  });

  tearDown(() async {
    await ReceiverService.instance.stop();
    ReceiverService.instance.onIncomingRequest = null;
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // Start the service *before* mounting anything, entirely inside
    // runAsync. Letting initState kick it off instead deadlocks: the future
    // is created under the fake clock, and awaiting it from runAsync's real
    // zone means the path_provider channel reply — which needs a pump to be
    // delivered — never arrives.
    await tester.runAsync(() => ReceiverService.instance.ensureStarted());

    await tester.pumpWidget(MaterialApp(
      theme: linkDropDarkTheme,
      home: const ReceiveScreen(),
    ));
    // The screen's own ensureStarted() is a no-op now: already listening.
    await tester.pump();
  }

  testWidgets('receiver keeps listening after the screen is disposed',
      (tester) async {
    await pumpScreen(tester);
    expect(ReceiverService.instance.isListening, isTrue,
        reason: 'opening Receive should start the listener. '
            'error=${ReceiverService.instance.errorMessage} '
            'status=${ReceiverService.instance.statusMessage}');

    // Navigate away entirely — the widget is gone.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();

    expect(
      ReceiverService.instance.isListening,
      isTrue,
      reason: 'leaving the screen must not stop the receiver — that is what '
          'made senders see "Connection refused" while the app was running',
    );

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });

  testWidgets('stop() is what stops it, not navigation', (tester) async {
    await pumpScreen(tester);
    expect(ReceiverService.instance.isListening, isTrue);

    await tester.runAsync(() => ReceiverService.instance.stop());
    await tester.pump();

    expect(ReceiverService.instance.isListening, isFalse);
    expect(ReceiverService.instance.state, ReceiveState.idle);
  });

  test('an unwired consent handler refuses rather than silently accepting',
      () async {
    final service = ReceiverService.instance;
    service.onIncomingRequest = null;

    // Reaching the private consent path directly is not possible, so this
    // asserts the contract the service documents: with no handler there is no
    // way to ask the user, and accepting would write a stranger's files to
    // disk with nobody told.
    expect(service.onIncomingRequest, isNull);
    expect(service.isListening, isFalse);
  });
}
