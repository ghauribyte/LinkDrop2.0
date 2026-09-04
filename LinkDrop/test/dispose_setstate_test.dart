import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/screens/device_list_screen.dart';

void main() {
  // Regression: DiscoveryBroadcaster.stop() fires onStatus synchronously,
  // and dispose() calls it. `mounted` is still true for the duration of
  // dispose(), so a bare `if (!mounted)` guard let setState() through on a
  // defunct element and tripped the framework assertion at framework.dart
  // '_lifecycleState != _ElementLifecycle.defunct'.
  testWidgets('tearing down DeviceListScreen does not setState after dispose',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeviceListScreen()));
    await tester.pump();

    // Replace the screen — this disposes it, running the stop() path.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(tester.takeException(), isNull);

    // _announceLoop parks on Future.delayed(interval) between sends, so one
    // timer outlives stop(). Let it elapse: the loop re-checks _running,
    // sees false and exits, rather than leaving a timer pending at teardown.
    await tester.pump(const Duration(seconds: 3));
  });
}
