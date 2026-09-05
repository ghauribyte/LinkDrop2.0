import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/cert_manager.dart';
import '../engine/device_identity.dart';
import '../engine/discovery_broadcaster.dart';
import '../engine/file_receiver.dart';
import '../engine/media_export.dart';
import '../engine/notification_permission.dart';
import '../engine/received_log.dart';
import '../engine/throughput_meter.dart';
import '../engine/transfer_wake_lock.dart';
import '../models/manifest_entry.dart';
import '../models/transfer_progress.dart';

/// One line in the Recent list. A decline is recorded alongside completions
/// rather than hidden — it is a normal outcome, not a failure.
class RecentEntry {
  RecentEntry({required this.label, required this.time, this.declined = false});

  final String label;
  final DateTime time;
  final bool declined;

  String get clock =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

enum ReceiveState { idle, receiving, complete, declined, failed }

/// Owns the receiving side of LinkDrop for the lifetime of the app rather
/// than the lifetime of a screen.
///
/// This used to live in ReceiveScreen's State, which meant dispose() called
/// FileReceiver.stop() and DiscoveryBroadcaster.stop(). Leaving the Receive
/// screen — switching rail destinations, backing out, glancing at another
/// screen — therefore closed the listening sockets while the app carried on
/// running, and a sender that had already found this device got a bare
/// "Connection refused" with nothing explaining why. On a phone that is
/// trivially easy to trigger.
///
/// Listening is now explicit state the user turns on and off, not a side
/// effect of which screen happens to be visible. [ReceiveScreen] is a view
/// over this service: it attaches to the notifications and offers a stop
/// control, but navigating away no longer tears anything down.
///
/// UI-free by the same rule as `lib/engine/` (Decision 008), with one
/// deliberate seam: [onIncomingRequest] is supplied by the app, because the
/// accept/reject surface needs a Navigator and this class must not import
/// one. If nothing has been wired the transfer is refused rather than
/// silently accepted — see [_askConsent].
class ReceiverService extends ChangeNotifier {
  ReceiverService._();

  static final ReceiverService instance = ReceiverService._();

  DiscoveryBroadcaster? _broadcaster;
  FileReceiver? _receiver;
  Future<void>? _starting;

  final _wakeLock = TransferWakeLock();
  final meter = ThroughputMeter();

  /// Supplied by the app, since showing the consent surface needs a
  /// Navigator. Returns whether the batch was accepted.
  Future<bool> Function(List<ManifestEntry> files, String senderIp)?
      onIncomingRequest;

  bool _listening = false;
  bool get isListening => _listening;

  ReceiveState state = ReceiveState.idle;
  String? statusMessage;
  String? errorMessage;
  TransferProgress? progress;
  DeviceIdentity? identity;
  Directory? receivedDir;

  /// The manifest of the batch being received, so a weighted progress bar can
  /// size its segments. Cleared when the batch ends.
  List<ManifestEntry> incoming = [];
  final List<RecentEntry> recents = [];

  void _update(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  /// Starts listening if it is not already. Safe to call from every screen
  /// build or initState — concurrent callers await the same start rather
  /// than racing two receivers onto the same port.
  Future<void> ensureStarted() {
    if (_listening) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    // Asked here, before anything can arrive, because the alternative is a
    // permission dialog appearing on top of a running transfer. Without it
    // the foreground service's notification is silently suppressed on
    // Android 13+, so a long transfer is protected but invisible.
    await NotificationPermission.ensureRequested();

    // path_provider is a platform channel, so it can fail — no implementation
    // on the host, or a platform that refuses a documents directory.
    final Directory docsDir;
    try {
      docsDir = await getApplicationDocumentsDirectory();
    } catch (e) {
      _update(() {
        state = ReceiveState.failed;
        errorMessage = 'Could not find a place to save files: $e';
      });
      return;
    }

    final linkdropDir = Directory('${docsDir.path}/linkdrop');
    final certPath = '${linkdropDir.path}/cert.pem';
    final keyPath = '${linkdropDir.path}/key.pem';

    try {
      await CertManager.ensureCertExists(certPath: certPath, keyPath: keyPath);
    } catch (e) {
      _update(() {
        state = ReceiveState.failed;
        errorMessage = 'Could not generate certificate: $e';
      });
      return;
    }

    final resolved = await DeviceIdentity.resolve(certPath: certPath);
    _update(() => identity = resolved);

    receivedDir = Directory('${linkdropDir.path}/received');

    // Sweep up anything stranded by an earlier run before listening again.
    //
    // Strictly sequential, and that ordering is load-bearing: clearPending
    // deletes gallery rows still marked pending, while _publishBacklog
    // *creates* rows that are pending until their bytes finish copying. Run
    // concurrently, the cleanup deletes the very files the backlog sweep is
    // exporting and they never reach the gallery.
    unawaited(() async {
      await MediaExport.clearPending();
      await _publishBacklog();
    }());

    _broadcaster = DiscoveryBroadcaster(
      deviceName: Platform.localHostname,
      onStatus: (msg) => _update(() => statusMessage = msg),
      onError: (e) => _update(() => errorMessage = 'Broadcast error: $e'),
    );

    _receiver = FileReceiver(
      targetDir: receivedDir!,
      certPath: certPath,
      keyPath: keyPath,
      onStatus: (msg) => _update(() => statusMessage = msg),
      onIncomingRequest: _askConsent,
      onProgress: (p) => _update(() {
        state = ReceiveState.receiving;
        progress = p;
        meter.update(_batchBytesDoneFor(p));
      }),
      onComplete: (filename) {
        _update(() {
          recents.insert(
            0,
            RecentEntry(label: filename, time: DateTime.now()),
          );
        });
        _recordReceived(filename);
        _publishToGallery(filename);
      },
      onBatchComplete: (count) => _update(() {
        state = ReceiveState.complete;
        statusMessage = count == 1
            ? 'Transfer complete.'
            : 'Transfer complete ($count files).';
        progress = null;
        incoming = [];
        meter.reset();
        _wakeLock.release();
      }),
      // onError is a genuine failure; onRejected is an expected outcome.
      // They must not collapse into the same visual state (Decision 014).
      onError: (msg) => _update(() {
        state = ReceiveState.failed;
        errorMessage = msg;
        progress = null;
        meter.reset();
        _wakeLock.release();
      }),
      onRejected: (msg) => _update(() {
        state = ReceiveState.declined;
        statusMessage = msg;
        progress = null;
        incoming = [];
        meter.reset();
        _wakeLock.release();
      }),
    );

    await _broadcaster!.start();
    final started = await _receiver!.start();

    // FileReceiver.start() returns false with an error callback rather than
    // throwing, so the flag has to follow its result — claiming to listen
    // when the port never opened is exactly the confusion this class exists
    // to remove.
    _update(() => _listening = started != false);
  }

  /// Stops listening and announcing. Explicit: nothing else in the app calls
  /// this, which is the entire point.
  Future<void> stop() async {
    _broadcaster?.stop();
    _receiver?.stop();
    _broadcaster = null;
    _receiver = null;
    await _wakeLock.release();
    _update(() {
      _listening = false;
      state = ReceiveState.idle;
      progress = null;
      incoming = [];
      statusMessage = null;
      meter.reset();
    });
  }

  /// Clears a finished/failed/declined outcome back to waiting, without
  /// touching the sockets.
  void acknowledgeOutcome() {
    if (state == ReceiveState.receiving) return;
    _update(() {
      state = ReceiveState.idle;
      errorMessage = null;
      statusMessage = null;
      progress = null;
      incoming = [];
    });
  }

  Future<bool> _askConsent(List<ManifestEntry> files, String senderIp) async {
    _update(() => incoming = files);

    final handler = onIncomingRequest;
    if (handler == null) {
      // No surface available to ask with. Refusing is the only safe answer:
      // accepting would write a stranger's files to disk with nobody told.
      _update(() {
        incoming = [];
        state = ReceiveState.declined;
        statusMessage = 'Declined — the app could not ask for confirmation.';
      });
      return false;
    }

    final accepted = await handler(files, senderIp);

    // From here until onBatchComplete/onError, bytes are moving — exactly
    // the window a screen timeout must not interrupt.
    if (accepted) {
      await _wakeLock.acquire();
    } else {
      _update(() {
        state = ReceiveState.declined;
        incoming = [];
        recents.insert(
          0,
          RecentEntry(
            label: 'declined from $senderIp',
            time: DateTime.now(),
            declined: true,
          ),
        );
      });
    }
    return accepted;
  }

  /// Bytes finished across the whole batch, not just the current file, so the
  /// measured rate does not reset at every file boundary.
  int _batchBytesDoneFor(TransferProgress p) {
    final currentIndex = p.fileIndex - 1;
    var done = 0;
    for (var i = 0; i < currentIndex && i < incoming.length; i++) {
      done += incoming[i].size;
    }
    return done + p.bytesDone;
  }

  /// Adds a completed file to the durable received log.
  ///
  /// Written before the gallery export so the entry survives an export
  /// failure — a file the user can still open from its staging path beats one
  /// that vanishes from the list because publishing broke. The `content://`
  /// URI is filled in afterwards by [_publishToGallery].
  Future<void> _recordReceived(String filename) async {
    final dir = receivedDir;
    if (dir == null) return;

    final file = File('${dir.path}/$filename');
    int size;
    try {
      size = await file.length();
    } catch (_) {
      return;
    }

    try {
      await ReceivedLog(directory: dir).add(ReceivedFile(
        name: filename,
        path: file.path,
        bytes: size,
        receivedAt: DateTime.now(),
      ));
    } catch (_) {
      // History is a convenience; never surface it as a transfer error.
    }
  }

  /// Moves a completed file out of app-private storage into the system media
  /// collections, so received photos actually appear in the gallery.
  ///
  /// The staging copy is removed once the export succeeds, making this a move
  /// rather than a duplicate. If the export fails the file is left where it
  /// is, so a gallery problem never costs the user the transfer.
  ///
  /// No-op on Linux, where the received folder is already user-visible.
  Future<void> _publishToGallery(String filename) async {
    final dir = receivedDir;
    if (dir == null || !MediaExport.isSupported) return;

    final staged = File('${dir.path}/$filename');
    final uri = await MediaExport.export(
      path: staged.path,
      filename: filename,
      onError: (msg) => _update(() => statusMessage = msg),
    );
    if (uri == null) return;

    // The staging copy is about to be deleted, so the MediaStore URI becomes
    // the only way to open this file — record it before the path it was
    // logged under stops resolving.
    try {
      await ReceivedLog(directory: dir)
          .setContentUri(path: staged.path, contentUri: uri);
    } catch (_) {
      // Non-fatal: the entry simply keeps its (now stale) path.
    }

    try {
      await staged.delete();
    } catch (_) {
      // Nothing actionable — the published copy is the one that counts.
    }
    _update(() => statusMessage = 'Saved to gallery: $filename');
  }

  /// Publishes anything already sitting in the staging directory.
  ///
  /// Since a successful export deletes the staged copy, whatever is still
  /// here on startup is by definition unpublished, so this sweep is safe to
  /// repeat. Failures stay silent: this is background tidying, and it must
  /// not overwrite the status line of a live transfer.
  Future<void> _publishBacklog() async {
    final dir = receivedDir;
    if (dir == null || !MediaExport.isSupported) return;
    if (!await dir.exists()) return;

    final List<FileSystemEntity> stale;
    try {
      stale = await dir.list().toList();
    } catch (_) {
      return;
    }

    for (final entity in stale) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      // The log itself lives in this directory and is not a received file.
      if (name == 'received_log.json') continue;

      final uri = await MediaExport.export(path: entity.path, filename: name);
      if (uri == null) continue;
      try {
        await entity.delete();
      } catch (_) {
        // Leave it; the published copy is the one that counts.
      }
    }
  }
}
