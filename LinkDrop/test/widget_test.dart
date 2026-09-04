import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/main.dart';

/// Smoke test for the app shell.
///
/// This file used to be the untouched Flutter counter scaffold, importing a
/// `package:linkdrop_app` that does not exist (the package is `linkdrop`) and
/// a `MyApp` that was never written — so it failed to compile on every run.
void main() {
  testWidgets('app builds and lands on a screen', (tester) async {
    await tester.pumpWidget(const LinkDropApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
