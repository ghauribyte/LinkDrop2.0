import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the device awake for the duration of an active send or receive.
///
/// A transfer runs as a plain background socket, not a foreground service.
/// Without this, a screen timeout partway through a transfer can let Android
/// suspend the app's network — the peer sees that as the connection being
/// reset (`errno 104`), which looks like a network bug but is really the OS
/// doing exactly what an unprotected background app should expect.
///
/// UI-free per the rest of `lib/engine/` (Decision 008): it holds no
/// widgets and reports nothing outward. A screen calls [acquire] when a
/// transfer starts and [release] when it ends, in every terminal state
/// (done, failed, cancelled, rejected) and in `dispose()` — a wake lock
/// left held after the screen that requested it is gone drains battery for
/// no reason.
///
/// No-op on non-Android platforms: Linux has no comparable OS-level network
/// suspension to protect against, and desktop screen timeouts don't tear
/// down sockets the way Android's Doze/App Standby can.
class TransferWakeLock {
  TransferWakeLock();

  static const _channel = MethodChannel('linkdrop/wake_lock');

  /// The native lock is acquired with a timeout as a safety net against a
  /// leaked lock if release is ever missed (a crash, an unhandled
  /// exception) — it must not survive forever. This timer re-acquires
  /// before that timeout expires, so a transfer slower than one interval
  /// doesn't lose the protection partway through.
  static const _renewEvery = Duration(minutes: 4);

  Timer? _renewTimer;
  bool _held = false;

  bool get isSupported => Platform.isAndroid;

  Future<void> acquire() async {
    if (!isSupported || _held) return;
    _held = true;
    await _tryAcquire();
    _renewTimer = Timer.periodic(_renewEvery, (_) => _tryAcquire());
  }

  Future<void> release() async {
    if (!isSupported || !_held) return;
    _held = false;
    _renewTimer?.cancel();
    _renewTimer = null;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {
      // Nothing actionable — worst case the native timeout expires on its
      // own in a few minutes.
    }
  }

  Future<void> _tryAcquire() async {
    try {
      await _channel.invokeMethod('acquire');
    } catch (_) {
      // Non-fatal: the transfer proceeds without the protection, same as
      // before this existed.
    }
  }
}
