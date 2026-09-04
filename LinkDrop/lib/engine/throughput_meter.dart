/// Measures transfer speed and estimates time remaining.
///
/// UI-free by the same rule as the rest of `lib/engine/` (Decision 008): it
/// holds no widgets and reports nothing outward. A caller feeds it cumulative
/// byte counts and reads [bytesPerSecond] / [etaFor] whenever it wants to
/// draw.
///
/// The rate is taken over a sliding window rather than the whole transfer, so
/// it reflects what the link is doing *now*. A transfer that starts fast over
/// Wi-Fi Direct and then degrades should show the degraded number, not an
/// average that stays optimistic for the rest of the batch.
class ThroughputMeter {
  ThroughputMeter({
    this.window = const Duration(seconds: 5),
    this.minimumSample = const Duration(milliseconds: 600),
  });

  /// How far back the rate is averaged.
  final Duration window;

  /// Below this much elapsed data the rate is not reported at all. Dividing
  /// a handful of bytes by a few milliseconds produces a wild number that
  /// would show up as a flickering headline, so early on we say nothing
  /// rather than something wrong.
  final Duration minimumSample;

  final List<({Duration at, int bytes})> _samples = [];
  final Stopwatch _clock = Stopwatch();

  /// Cumulative bytes at the most recent sample.
  int get bytesDone => _samples.isEmpty ? 0 : _samples.last.bytes;

  /// Record the cumulative byte total for the transfer so far.
  ///
  /// Takes a running total, not a delta, so a caller that already tracks
  /// "bytes done" can hand over the same number it draws with, and a
  /// duplicate or out-of-order call cannot inflate the rate.
  void update(int cumulativeBytes) {
    if (!_clock.isRunning) _clock.start();
    final now = _clock.elapsed;

    _samples.add((at: now, bytes: cumulativeBytes));

    // Keep one sample older than the window so the span covers the full
    // window rather than collapsing to the newest point.
    final cutoff = now - window;
    var drop = 0;
    while (drop + 1 < _samples.length && _samples[drop + 1].at < cutoff) {
      drop++;
    }
    if (drop > 0) _samples.removeRange(0, drop);
  }

  /// Pause and resume, so idle time does not count against the rate.
  void pause() => _clock.stop();
  void resume() {
    if (!_clock.isRunning) _clock.start();
    // The gap while paused is not transfer time; drop history so the next
    // rate is measured from here rather than across the pause.
    if (_samples.isNotEmpty) {
      _samples
        ..clear()
        ..add((at: _clock.elapsed, bytes: bytesDone));
    }
  }

  void reset() {
    _samples.clear();
    _clock
      ..stop()
      ..reset();
  }

  /// Bytes per second over the window, or null when there is not yet enough
  /// data to say honestly.
  double? get bytesPerSecond {
    if (_samples.length < 2) return null;

    final first = _samples.first;
    final last = _samples.last;
    final span = last.at - first.at;
    if (span < minimumSample) return null;

    final bytes = last.bytes - first.bytes;
    if (bytes <= 0) return null;

    return bytes / (span.inMicroseconds / Duration.microsecondsPerSecond);
  }

  /// Time to move [remainingBytes] at the current rate, or null if the rate
  /// is unknown. Returns null for a stalled transfer rather than infinity.
  Duration? etaFor(int remainingBytes) {
    if (remainingBytes <= 0) return Duration.zero;
    final rate = bytesPerSecond;
    if (rate == null || rate <= 0) return null;

    final seconds = remainingBytes / rate;
    // Beyond an hour the estimate is noise; callers show nothing instead.
    if (seconds > 3600) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// "7.3 MB/s", or null when the rate is unknown.
  String? get rateLabel {
    final rate = bytesPerSecond;
    if (rate == null) return null;
    return '${formatRate(rate)}/s';
  }

  /// "19 s left" / "2 min left", or null when unknown.
  String? etaLabel(int remainingBytes) {
    final eta = etaFor(remainingBytes);
    if (eta == null) return null;
    return '${formatDuration(eta)} left';
  }
}

/// Formats a byte rate at the largest sensible unit.
String formatRate(double bytesPerSecond) {
  const kb = 1024.0;
  const mb = kb * 1024;
  const gb = mb * 1024;

  if (bytesPerSecond >= gb) {
    return '${(bytesPerSecond / gb).toStringAsFixed(1)} GB';
  }
  if (bytesPerSecond >= mb) {
    return '${(bytesPerSecond / mb).toStringAsFixed(1)} MB';
  }
  if (bytesPerSecond >= kb) {
    return '${(bytesPerSecond / kb).toStringAsFixed(0)} KB';
  }
  return '${bytesPerSecond.round()} B';
}

/// Coarse duration for a countdown: seconds under a minute, then minutes.
///
/// Deliberately low precision — an ETA that reads "1 m 47 s" invites the user
/// to notice it was wrong.
String formatDuration(Duration d) {
  final seconds = d.inSeconds;
  if (seconds < 1) return 'under 1 s';
  if (seconds < 60) return '$seconds s';

  final minutes = d.inMinutes;
  if (minutes < 60) return '$minutes min';

  final hours = d.inHours;
  final remainingMinutes = minutes - hours * 60;
  return remainingMinutes == 0 ? '$hours h' : '$hours h $remainingMinutes min';
}
