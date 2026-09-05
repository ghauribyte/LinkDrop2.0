import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/screens/received_files_screen.dart';

/// Pins a bug where the screen always showed "no files yet" no matter how
/// many files had actually arrived.
///
/// ReceiverService writes received_log.json beside the staged files, at
/// `<documents>/linkdrop/received/`. This screen read from `<documents>/linkdrop/`
/// instead — one directory too shallow — so ReceivedLog.load() always found
/// nothing there and the list was permanently empty, regardless of history.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a file the receiver actually logged', (tester) async {
    final docs = Directory.systemTemp.createTempSync('linkdrop_received_test_');
    addTearDown(() {
      if (docs.existsSync()) docs.deleteSync(recursive: true);
    });

    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );

    // The exact path ReceiverService._recordReceived writes to: staging and
    // the log sit together under linkdrop/received/, not linkdrop/ itself.
    final receivedDir = Directory('${docs.path}/linkdrop/received')
      ..createSync(recursive: true);
    File('${receivedDir.path}/received_log.json').writeAsStringSync(
      jsonEncode([
        {
          'name': 'photo.jpg',
          'path': '${receivedDir.path}/photo.jpg',
          'bytes': 12345,
          'receivedAt': DateTime.now().toIso8601String(),
        },
      ]),
    );

    await tester.pumpWidget(
      const MaterialApp(home: ReceivedFilesScreen()),
    );

    // The load is real disk I/O; pumpAndSettle drives a fake clock and would
    // spin forever, so step outside it the same way the golden tests do. A
    // single delay-then-pump settles the *empty* case (see the golden
    // tests), but a real read-then-rebuild needs a few more turns of the
    // loop, so this polls instead of guessing a fixed wait.
    for (var i = 0; i < 10; i++) {
      if (find.text('photo.jpg').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('Nothing received yet'), findsNothing);
  });
}
