import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/engine/throughput_meter.dart';

/// The meter drives a number the user reads and trusts, so the cases that
/// matter are the ones where it should refuse to answer.
void main() {
  group('ThroughputMeter', () {
    test('reports nothing until there is enough elapsed data', () {
      final meter = ThroughputMeter();
      expect(meter.bytesPerSecond, isNull);

      meter.update(1024);
      // A single sample has no span to divide by.
      expect(meter.bytesPerSecond, isNull);
      expect(meter.rateLabel, isNull);
    });

    test('measures a rate once the minimum sample has elapsed', () async {
      final meter = ThroughputMeter(
        minimumSample: const Duration(milliseconds: 50),
      );

      meter.update(0);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      meter.update(120 * 1024);

      final rate = meter.bytesPerSecond;
      expect(rate, isNotNull);
      // ~1 MB/s, but wall-clock timing in a test is loose: assert the order
      // of magnitude rather than a value that would flake.
      expect(rate!, greaterThan(200 * 1024));
      expect(rate, lessThan(8 * 1024 * 1024));
    });

    test('takes cumulative totals, so a repeated value is not new bytes',
        () async {
      final meter = ThroughputMeter(
        minimumSample: const Duration(milliseconds: 50),
      );

      meter.update(5000);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      meter.update(5000);

      // No progress between samples means no rate, not a rate of zero
      // dressed up as a number.
      expect(meter.bytesPerSecond, isNull);
      expect(meter.bytesDone, 5000);
    });

    test('eta is zero when nothing remains and null when stalled', () {
      final meter = ThroughputMeter();
      expect(meter.etaFor(0), Duration.zero);
      // Rate unknown, so no honest estimate exists.
      expect(meter.etaFor(1000), isNull);
      expect(meter.etaLabel(1000), isNull);
    });

    test('reset clears history', () async {
      final meter = ThroughputMeter(
        minimumSample: const Duration(milliseconds: 50),
      );
      meter.update(0);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      meter.update(100000);
      expect(meter.bytesPerSecond, isNotNull);

      meter.reset();
      expect(meter.bytesPerSecond, isNull);
      expect(meter.bytesDone, 0);
    });
  });

  group('formatRate', () {
    test('picks the largest sensible unit', () {
      expect(formatRate(512), '512 B');
      expect(formatRate(2048), '2 KB');
      expect(formatRate(7.3 * 1024 * 1024), '7.3 MB');
      expect(formatRate(2.0 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });

  group('formatDuration', () {
    test('stays coarse', () {
      expect(formatDuration(const Duration(milliseconds: 400)), 'under 1 s');
      expect(formatDuration(const Duration(seconds: 19)), '19 s');
      expect(formatDuration(const Duration(seconds: 90)), '1 min');
      expect(formatDuration(const Duration(hours: 2)), '2 h');
      expect(formatDuration(const Duration(hours: 2, minutes: 5)), '2 h 5 min');
    });
  });
}
