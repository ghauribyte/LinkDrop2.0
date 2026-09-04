import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/cert_manager.dart';
import '../engine/device_identity.dart';
import '../engine/discovery_broadcaster.dart';
import '../engine/file_receiver.dart';
import '../engine/media_export.dart';
import '../engine/received_log.dart';
import '../engine/throughput_meter.dart';
import '../engine/transfer_wake_lock.dart';
import '../models/manifest_entry.dart';
import '../models/transfer_progress.dart';
import '../theme/linkdrop_theme.dart';
import '../widgets/consent_surface.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import '../widgets/transfer_progress_view.dart';

/// One line in the session's Recent list. A decline is recorded alongside
/// completions rather than hidden — it is a normal outcome, not a failure.
class _RecentEntry {
  _RecentEntry({required this.label, required this.time, this.declined = false});

  final String label;
  final DateTime time;
  final bool declined;

  String get clock =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

enum _ReceiveState { idle, receiving, complete, declined, failed }

/// Runs the receiving side of LinkDrop as a real device:
/// - Broadcasts this device's presence
/// - Listens for incoming files via FileReceiver
/// - Shows an accept/reject surface before any file is written to disk
/// - Shows live progress once a transfer is accepted
///
/// Cert/key at `<app documents dir>/linkdrop/cert.pem` and `key.pem` are
/// generated in-app on first launch via CertManager (Decision 015) —
/// no openssl/shell step required, so this works on Android too.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  DiscoveryBroadcaster? _broadcaster;
  FileReceiver? _receiver;

  /// Where FileReceiver stages incoming files, kept so completed ones can be
  /// located and published to the gallery. See [_publishToGallery].
  Directory? _receivedDir;

  _ReceiveState _state = _ReceiveState.idle;
  String? _statusMessage;
  String? _errorMessage;
  TransferProgress? _progress;
  DeviceIdentity? _identity;

  /// The manifest of the batch being received, so the weighted batch bar can
  /// size its segments. Cleared when the batch ends.
  List<ManifestEntry> _incoming = [];
  final List<_RecentEntry> _recents = [];

  /// Set at the top of [dispose] so engine callbacks stop touching state.
  /// `mounted` alone is not enough: it is still true for the duration of
  /// dispose(), and DiscoveryBroadcaster.stop() fires onStatus synchronously
  /// from inside it.
  bool _disposed = false;

  /// Measures throughput for the rate and ETA readout.
  final _meter = ThroughputMeter();

  /// Keeps Android awake for the duration of an accepted transfer — see
  /// transfer_wake_lock.dart for why a plain background socket needs this.
  final _wakeLock = TransferWakeLock();

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  /// Bytes finished across the whole batch, not just the current file, so the
  /// measured rate does not reset at every file boundary.
  int _batchBytesDoneFor(TransferProgress p) {
    final currentIndex = p.fileIndex - 1;
    var done = 0;
    for (var i = 0; i < currentIndex && i < _incoming.length; i++) {
      done += _incoming[i].size;
    }
    return done + p.bytesDone;
  }

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    // path_provider is a platform channel, so it can fail — no implementation
    // on the host, or a platform that refuses a documents directory. An
    // unguarded await here took the screen down with an unhandled exception
    // instead of showing why receiving could not start.
    final Directory docsDir;
    try {
      docsDir = await getApplicationDocumentsDirectory();
    } catch (e) {
      _safeSetState(() {
        _state = _ReceiveState.failed;
        _errorMessage = 'Could not find a place to save files: $e';
      });
      return;
    }

    final linkdropDir = Directory('${docsDir.path}/linkdrop');
    final certPath = '${linkdropDir.path}/cert.pem';
    final keyPath = '${linkdropDir.path}/key.pem';

    try {
      await CertManager.ensureCertExists(certPath: certPath, keyPath: keyPath);
    } catch (e) {
      _safeSetState(() {
        _state = _ReceiveState.failed;
        _errorMessage = 'Could not generate certificate: $e';
      });
      return;
    }

    final identity = await DeviceIdentity.resolve(certPath: certPath);
    _safeSetState(() => _identity = identity);

    _receivedDir = Directory('${linkdropDir.path}/received');

    // Sweep up anything stranded by an earlier run before listening again.
    unawaited(_publishBacklog());

    _broadcaster = DiscoveryBroadcaster(
      deviceName: Platform.localHostname,
      onStatus: (msg) => _safeSetState(() => _statusMessage = msg),
      onError: (e) =>
          _safeSetState(() => _errorMessage = 'Broadcast error: $e'),
    );

    _receiver = FileReceiver(
      targetDir: _receivedDir!,
      certPath: certPath,
      keyPath: keyPath,
      onStatus: (msg) => _safeSetState(() => _statusMessage = msg),
      onIncomingRequest: _handleIncomingRequest,
      onProgress: (p) => _safeSetState(() {
        _state = _ReceiveState.receiving;
        _progress = p;
        _meter.update(_batchBytesDoneFor(p));
      }),
      onComplete: (filename) {
        _safeSetState(() {
          _recents.insert(
            0,
            _RecentEntry(label: filename, time: DateTime.now()),
          );
        });
        _recordReceived(filename);
        _publishToGallery(filename);
      },
      onBatchComplete: (count) => _safeSetState(() {
        _state = _ReceiveState.complete;
        _statusMessage = count == 1
            ? 'Transfer complete.'
            : 'Transfer complete ($count files).';
        _progress = null;
        _incoming = [];
        _meter.reset();
        _wakeLock.release();
      }),
      // onError is a genuine failure; onRejected is an expected outcome.
      // They must not collapse into the same visual state.
      onError: (msg) => _safeSetState(() {
        _state = _ReceiveState.failed;
        _errorMessage = msg;
        _progress = null;
        _meter.reset();
        _wakeLock.release();
      }),
      onRejected: (msg) => _safeSetState(() {
        _state = _ReceiveState.declined;
        _statusMessage = msg;
        _progress = null;
        _incoming = [];
        _meter.reset();
        _wakeLock.release();
      }),
    );

    await _broadcaster!.start();
    await _receiver!.start();
  }

  Future<bool> _handleIncomingRequest(
    List<ManifestEntry> files,
    String senderIp,
  ) async {
    if (_disposed || !mounted) return false;

    _safeSetState(() => _incoming = files);

    final accepted = await showIncomingRequest(
      context,
      files: files,
      senderIp: senderIp,
      destination: _receivedDir?.path ?? 'this device',
      fingerprint: _identity?.shortFingerprint,
      senderIsPhone: !Platform.isAndroid,
    );

    // From here until onBatchComplete/onError, bytes are moving — this is
    // exactly the window a screen timeout must not interrupt.
    if (accepted) await _wakeLock.acquire();

    if (!accepted) {
      _safeSetState(() {
        _state = _ReceiveState.declined;
        _incoming = [];
        _recents.insert(
          0,
          _RecentEntry(
            label: 'declined from $senderIp',
            time: DateTime.now(),
            declined: true,
          ),
        );
      });
    }
    return accepted;
  }

  /// Moves a completed file out of app-private storage into the system media
  /// collections, so received photos actually appear in the gallery. Runs per
  /// file from onComplete — only whole files get published.
  ///
  /// The staging copy is removed once the export succeeds, making this a move
  /// rather than a duplicate. If the export fails the file is left where it
  /// is, so a gallery problem never costs the user the transfer.
  ///
  /// No-op on Linux, where the received folder is already user-visible.
  /// Adds a completed file to the durable received log.
  ///
  /// Written before the gallery export so the entry survives an export
  /// failure — a file the user can still open from its staging path is
  /// better than one that vanishes from the list because publishing broke.
  /// The `content://` URI is filled in afterwards by [_publishToGallery].
  ///
  /// Failures here are silent: the transfer itself succeeded, and losing a
  /// history row must not be reported as the transfer going wrong.
  Future<void> _recordReceived(String filename) async {
    final dir = _receivedDir;
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
      // History is a convenience; never surface this as a transfer error.
    }
  }

  Future<void> _publishToGallery(String filename) async {
    final dir = _receivedDir;
    if (dir == null || !MediaExport.isSupported) return;

    final staged = File('${dir.path}/$filename');
    final uri = await MediaExport.export(
      path: staged.path,
      filename: filename,
      onError: (msg) => _safeSetState(() => _statusMessage = msg),
    );
    if (uri == null) return;

    // The staging copy is about to be deleted, so the MediaStore URI
    // becomes the only way to open this file — record it before the path
    // it was logged under stops resolving.
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
    _safeSetState(() => _statusMessage = 'Saved to gallery: $filename');
  }

  /// Publishes anything already sitting in the staging directory.
  ///
  /// Files that arrived before gallery export existed — or during a run where
  /// the export failed — are stranded in app-private storage where nothing but
  /// LinkDrop can see them. Since a successful export deletes the staged copy,
  /// whatever is still here on startup is by definition unpublished, and this
  /// sweep is safe to repeat.
  ///
  /// Failures stay silent: this is background tidying, not something the user
  /// asked for, and it must not overwrite the status line of a live transfer.
  Future<void> _publishBacklog() async {
    final dir = _receivedDir;
    if (dir == null || !MediaExport.isSupported) return;
    if (!await dir.exists()) return;

    final List<FileSystemEntity> stale;
    try {
      stale = await dir.list().toList();
    } catch (_) {
      return;
    }

    for (final entity in stale) {
      if (_disposed) return;
      if (entity is! File) continue;

      final name = entity.path.split(Platform.pathSeparator).last;
      final uri = await MediaExport.export(path: entity.path, filename: name);
      if (uri == null) continue;

      try {
        await entity.delete();
      } catch (_) {
        // The published copy is the one that counts.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _broadcaster?.stop();
    _receiver?.stop();
    _wakeLock.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LinkDropShell(
      title: 'Receive',
      // Waiting is a single centred subject; a live or finished transfer is a
      // list of files and reads from the top.
      centerContent: _state == _ReceiveState.idle,
      content: _buildContent(context),
      detail: _buildDetail(context),
      statusLine: _buildStatusLine(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final identity = _identity;

    switch (_state) {
      case _ReceiveState.receiving:
        final progress = _progress;
        if (progress == null) break;

        final total = _incoming.fold<int>(0, (sum, f) => sum + f.size);
        final currentIndex = progress.fileIndex - 1;
        var done = 0;
        for (var i = 0; i < currentIndex && i < _incoming.length; i++) {
          done += _incoming[i].size;
        }
        done += progress.bytesDone;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TransferHeadline(
              percent: total == 0 ? progress.fraction : done / total,
              currentName: progress.filename,
              fileIndex: progress.fileIndex,
              fileCount: progress.fileCount,
              doneLabel: formatBytes(done),
              totalLabel:
                  formatBytes(total == 0 ? progress.totalBytes : total),
              stateWord: 'Receiving',
              rate: _meter.rateLabel,
              eta: _meter.etaLabel(total - done),
            ),
            const SizedBox(height: 18),
            BatchProgressBar(
              files: [
                for (var i = 0; i < _incoming.length; i++)
                  BatchFile(
                    name: _incoming[i].name,
                    bytes: _incoming[i].size,
                    progress: i < currentIndex
                        ? 1.0
                        : i == currentIndex
                            ? progress.fraction
                            : 0.0,
                  ),
              ],
            ),
          ],
        );

      case _ReceiveState.complete:
        return _outcome(
          context,
          icon: Icons.check_circle_outline,
          color: context.transferColors.success,
          title: 'Transfer complete',
          detail: _statusMessage ?? 'All files received.',
        );

      case _ReceiveState.declined:
        return _outcome(
          context,
          icon: Icons.remove_circle_outline,
          color: context.transferColors.declined,
          title: 'Transfer declined',
          detail: _statusMessage ??
              'Nothing was written to disk. Still listening.',
        );

      case _ReceiveState.failed:
        return _outcome(
          context,
          icon: Icons.error_outline,
          color: scheme.error,
          title: 'Something went wrong',
          detail: _errorMessage ?? 'The transfer could not complete.',
        );

      case _ReceiveState.idle:
        break;
    }

    final address = identity?.ipAddress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        PulseEmptyState(
          icon: Icons.download_outlined,
          title: 'Waiting for incoming files',
          subtitle: address == null
              ? 'You will be asked before anything is written to disk.'
              : 'This machine is listening on $address. You will be asked '
                  'before anything is written to disk.',
        ),
        if (identity?.shortFingerprint != null) ...[
          const SizedBox(height: 24),
          const SectionLabel('This device'),
          const SizedBox(height: 8),
          FingerprintText(
            identity!.shortFingerprint!,
            note: 'compare on the sender',
          ),
        ],
        const SizedBox(height: 4),
        Text(
          '',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _outcome(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String detail,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 40, color: color),
        const SizedBox(height: 18),
        Text(title, style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(detail,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }

  /// Save location and this session's recents — real content for the second
  /// pane, so the desktop layout has something true to say.
  Widget? _buildDetail(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < Bp.phone) return null;

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Save location'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 17, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _receivedDir?.path ?? '…',
                    maxLines: 2,
                    style: text.bodySmall?.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Recent'),
          const SizedBox(height: 6),
          if (_recents.isEmpty)
            Text(
              'Nothing received yet this session.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final entry in _recents.take(8))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom:
                        BorderSide(color: scheme.outlineVariant, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      entry.declined
                          ? Icons.remove_circle_outline
                          : Icons.insert_drive_file_outlined,
                      size: 16,
                      color: entry.declined
                          ? context.transferColors.declined
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(fontSize: 13),
                      ),
                    ),
                    Text(
                      entry.clock,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget? _buildStatusLine(BuildContext context) {
    final address = _identity?.ipAddress;
    if (_state == _ReceiveState.failed) {
      return StatusLine(
        message: _errorMessage ?? 'Receiver stopped',
        live: false,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (address == null) return null;
    return StatusLine(message: 'Listening on $address');
  }
}
