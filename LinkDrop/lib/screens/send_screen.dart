import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../engine/cert_exchange.dart';
import '../engine/file_sender.dart';
import '../engine/throughput_meter.dart';
import '../models/device.dart';
import '../models/transfer_progress.dart';
import '../theme/linkdrop_theme.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import '../widgets/transfer_progress_view.dart';
import 'device_list_screen.dart';

/// [cancelled] is deliberately separate from [failed]: a user cancelling a
/// transfer is an expected outcome, not a fault, and renders in neutral grey
/// rather than error red. Same distinction the engine draws between
/// `onError` and `onRejected` (Decision 014).
enum _SendState {
  idle,
  pickingDevice,
  fetchingCert,
  sending,
  done,
  cancelled,
  failed,
}

/// Orchestrates the full send flow:
/// 1. Pick one or more files from disk (Decision 013 — multi-file)
/// 2. Pick a device from DeviceListScreen — or, if [presetDevice] is
///    given, skip discovery entirely and use that device directly.
///    This is how a private-mode connection (Wi-Fi Direct, hotspot)
///    reaches the transfer engine: those connections already know the
///    peer's IP from the platform API, so there's no need for UDP
///    broadcast discovery to also work over that interface.
/// 3. Fetch that device's cert automatically (Decision 011)
/// 4. Hand off to the existing, already-tested FileSender
///
/// This screen does not duplicate any transfer logic — it only wires
/// together engine pieces that already work on their own.
class SendScreen extends StatefulWidget {
  final Device? presetDevice;

  const SendScreen({super.key, this.presetDevice});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  _SendState _state = _SendState.idle;
  List<String> _filePaths = [];

  /// Byte size per picked file, in the same order as [_filePaths]. Needed for
  /// the weighted batch bar — a segment's width *is* its file's size.
  List<int> _fileSizes = [];

  Device? _device;
  String? _errorMessage;
  TransferProgress? _progress;

  FileSender? _sender;
  bool _isPaused = false;
  bool _disposed = false;

  /// Measures throughput for the rate and ETA readout. Owned by the screen
  /// rather than the sender so the engine keeps reporting raw byte counts.
  final _meter = ThroughputMeter();

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  int get _totalBytes => _fileSizes.fold(0, (sum, size) => sum + size);

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final paths =
        result.files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty) return;

    final sizes = <int>[];
    for (final path in paths) {
      try {
        sizes.add(await File(path).length());
      } catch (_) {
        sizes.add(0);
      }
    }

    _safeSetState(() {
      _filePaths = paths;
      _fileSizes = sizes;
      _errorMessage = null;
      _state = _SendState.idle;
    });

    if (widget.presetDevice != null) {
      _safeSetState(() => _device = widget.presetDevice);
    }
  }

  Future<void> _chooseDevice() async {
    _safeSetState(() => _state = _SendState.pickingDevice);

    final device = await Navigator.of(context).push<Device>(
      MaterialPageRoute(builder: (_) => const DeviceListScreen()),
    );

    if (device == null) {
      _safeSetState(() => _state = _SendState.idle);
      return;
    }
    _safeSetState(() {
      _device = device;
      _state = _SendState.idle;
    });
  }

  Future<void> _startSend() async {
    var device = _device;
    if (device == null) {
      await _chooseDevice();
      device = _device;
      if (device == null) return;
    }

    _safeSetState(() => _state = _SendState.fetchingCert);
    await _fetchCertAndSend(device);
  }

  Future<void> _fetchCertAndSend(Device device) async {
    final certPem = await fetchCert(ip: device.ipAddress);
    if (_disposed || !mounted) return;

    if (certPem == null) {
      _safeSetState(() {
        _state = _SendState.failed;
        _errorMessage =
            'Could not get ${device.name}\'s certificate. Make sure they '
            'have LinkDrop open and you\'re on the same network.';
      });
      return;
    }

    // FileSender expects a cert file path, not raw PEM text — write the
    // fetched cert to a temp file so the existing, already-tested FileSender
    // code doesn't need to change at all.
    final tempDir = await Directory.systemTemp.createTemp('linkdrop_cert_');
    final tempCertFile = File('${tempDir.path}/receiver_cert.pem');
    await tempCertFile.writeAsString(certPem);

    _safeSetState(() => _state = _SendState.sending);

    final sender = FileSender(
      receiverIp: device.ipAddress,
      filePaths: _filePaths,
      receiverCertPath: tempCertFile.path,
      onProgress: (p) => _safeSetState(() {
        _progress = p;
        // Feed the batch total, not the per-file count, so the rate stays
        // continuous across file boundaries instead of resetting at each one.
        _meter.update(_batchBytesDone);
      }),
      onPausedChanged: (paused) => _safeSetState(() {
        _isPaused = paused;
        paused ? _meter.pause() : _meter.resume();
      }),
      onComplete: () => _safeSetState(() => _state = _SendState.done),
      onError: (msg) => _safeSetState(() {
        // A cancel we initiated already moved us to `cancelled`; don't let a
        // trailing socket error relabel it as a failure.
        if (_state == _SendState.cancelled) return;
        _state = _SendState.failed;
        _errorMessage = msg;
      }),
    );

    _safeSetState(() => _sender = sender);
    await sender.send();
    await tempDir.delete(recursive: true);
  }

  void _reset() {
    _safeSetState(() {
      _state = _SendState.idle;
      _filePaths = [];
      _fileSizes = [];
      _device = widget.presetDevice;
      _errorMessage = null;
      _progress = null;
      _sender = null;
      _isPaused = false;
      _meter.reset();
    });
  }

  void _togglePause() {
    final sender = _sender;
    if (sender == null) return;
    sender.isPaused ? sender.resume() : sender.pause();
  }

  void _cancelTransfer() {
    _sender?.cancel();
    _safeSetState(() {
      _state = _SendState.cancelled;
      _isPaused = false;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    // Don't leave a paused send loop parked on a socket after the screen
    // is gone — cancel() releases it so it can unwind and close.
    _sender?.cancel();
    super.dispose();
  }

  String _nameOf(String path) => path.split(Platform.pathSeparator).last;

  /// Per-file progress across the whole batch: everything before the current
  /// file is done, the current one carries its fraction, the rest are ahead.
  List<BatchFile> get _batchFiles {
    final progress = _progress;
    final currentIndex = (progress?.fileIndex ?? 1) - 1;

    return [
      for (var i = 0; i < _filePaths.length; i++)
        BatchFile(
          name: _nameOf(_filePaths[i]),
          bytes: i < _fileSizes.length ? _fileSizes[i] : 0,
          progress: switch (_state) {
            _SendState.done => 1.0,
            _ when i < currentIndex => 1.0,
            _ when i == currentIndex => progress?.fraction ?? 0.0,
            _ => 0.0,
          },
        ),
    ];
  }

  /// Bytes finished across the batch, not just within the current file.
  int get _batchBytesDone {
    final progress = _progress;
    if (_state == _SendState.done) return _totalBytes;
    if (progress == null) return 0;

    final currentIndex = progress.fileIndex - 1;
    var done = 0;
    for (var i = 0; i < currentIndex && i < _fileSizes.length; i++) {
      done += _fileSizes[i];
    }
    return done + progress.bytesDone;
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.sizeOf(context).width < Bp.phone;

    return LinkDropShell(
      title: 'Send',
      // The queue is the design's left-hand pane: persistent, and always
      // something true to say once files are picked.
      detail: _filePaths.isEmpty ? null : _buildQueue(context),
      detailOnLeft: true,
      // Nothing picked yet: the drop zone is the whole screen's subject, so
      // it sits in the middle. Once there are files it becomes the top of a
      // top-down reading order.
      centerContent: _filePaths.isEmpty && _state == _SendState.idle,
      content: _buildContent(context, isPhone),
      actions: _buildActions(context, isPhone),
      statusLine: _buildStatusLine(context),
    );
  }

  // ---------------------------------------------------------------- queue

  Widget _buildQueue(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final files = _batchFiles;
    final currentIndex = (_progress?.fileIndex ?? 0) - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Queue', style: text.headlineMedium?.copyWith(fontSize: 20)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${files.length} files · ${formatBytes(_totalBytes)}',
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, i) => _QueueRow(
              file: files[i],
              isCurrent: i == currentIndex && _state == _SendState.sending,
              sending: _state == _SendState.sending,
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- content

  Widget _buildContent(BuildContext context, bool isPhone) {
    switch (_state) {
      case _SendState.sending:
      case _SendState.fetchingCert:
        return _buildTransferring(context);
      case _SendState.done:
        return _buildOutcome(
          context,
          icon: Icons.check_circle_outline,
          color: context.transferColors.success,
          title: 'Sent',
          detail: '${_filePaths.length} files · '
              '${formatBytes(_totalBytes)} to ${_device?.name ?? 'device'}',
        );
      case _SendState.cancelled:
        return _buildOutcome(
          context,
          icon: Icons.remove_circle_outline,
          color: context.transferColors.declined,
          title: 'Transfer cancelled',
          detail: 'Nothing further was sent. The files are untouched.',
        );
      case _SendState.failed:
        return _buildOutcome(
          context,
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          title: 'Transfer failed',
          detail: _errorMessage ?? 'Something went wrong.',
        );
      case _SendState.idle:
      case _SendState.pickingDevice:
        return _filePaths.isEmpty
            ? _buildEmpty(context, isPhone)
            : _buildReady(context, isPhone);
    }
  }

  Widget _buildEmpty(BuildContext context, bool isPhone) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 30, color: scheme.onSurfaceVariant),
            const SizedBox(height: 18),
            Text(
              isPhone ? 'No files chosen' : 'Drop files here',
              style: text.headlineMedium?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              isPhone
                  ? 'Pick photos, video or any file on this phone.'
                  : 'or choose them from disk — nothing is read until you send',
              textAlign: TextAlign.center,
              style:
                  text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _pickFiles,
              child: const Text('Choose files'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReady(BuildContext context, bool isPhone) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatBytes(_totalBytes),
          style: text.displaySmall?.copyWith(fontSize: isPhone ? 56 : 78),
        ),
        const SizedBox(height: 6),
        Text(
          '${_filePaths.length} '
          '${_filePaths.length == 1 ? 'file' : 'files'} ready',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        const SectionLabel('Target'),
        const SizedBox(height: 10),
        Row(
          children: [
            if (_device != null)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.primary, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smartphone_outlined,
                          size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _device!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_device != null) const SizedBox(width: 10),
            TextButton(
              onPressed: _chooseDevice,
              child: Text(_device == null ? 'Choose device' : 'Change device'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTransferring(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final progress = _progress;
    final total = _totalBytes;
    final done = _batchBytesDone;

    if (_state == _SendState.fetchingCert || progress == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PulseEmptyState(
            icon: Icons.send_outlined,
            title: 'Connecting to ${_device?.name ?? 'device'}…',
            subtitle: 'Verifying their certificate before anything is sent.',
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TransferHeadline(
          percent: total == 0 ? 0 : done / total,
          currentName: progress.filename,
          fileIndex: progress.fileIndex,
          fileCount: progress.fileCount,
          doneLabel: formatBytes(done),
          totalLabel: formatBytes(total),
          stateWord: _isPaused ? 'Paused' : 'Sending',
          paused: _isPaused,
          // Both stay null until the meter has seen enough to be honest, and
          // while paused, where a countdown would keep ticking against a
          // transfer that is not moving.
          rate: _isPaused ? null : _meter.rateLabel,
          eta: _isPaused ? null : _meter.etaLabel(total - done),
        ),
        const SizedBox(height: 18),
        BatchProgressBar(files: _batchFiles),
        const SizedBox(height: 14),
        if (_device != null)
          Text(
            'Direct link · this device → ${_device!.ipAddress}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildOutcome(
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
        Text(
          detail,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- actions

  Widget? _buildActions(BuildContext context, bool isPhone) {
    Widget row(List<Widget> children) => Row(
          mainAxisAlignment:
              isPhone ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            for (final child in children) ...[
              if (isPhone) Expanded(child: child) else child,
              if (child != children.last) const SizedBox(width: 10),
            ],
          ],
        );

    switch (_state) {
      case _SendState.sending:
        return row([
          TextButton.icon(
            onPressed: _togglePause,
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 18),
            label: Text(_isPaused ? 'Resume' : 'Pause'),
          ),
          TextButton.icon(
            onPressed: _cancelTransfer,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancel transfer'),
          ),
        ]);

      case _SendState.done:
      case _SendState.cancelled:
      case _SendState.failed:
        return row([
          OutlinedButton(
            onPressed: _reset,
            child: const Text('Send more files'),
          ),
        ]);

      case _SendState.idle:
        if (_filePaths.isEmpty) return null;
        return row([
          OutlinedButton.icon(
            onPressed: _startSend,
            icon: const Icon(Icons.send_outlined, size: 18),
            // The action names its own consequence.
            label: Text('Send ${_filePaths.length} '
                '${_filePaths.length == 1 ? 'file' : 'files'}'),
          ),
          TextButton(
            onPressed: _pickFiles,
            child: const Text('Change files'),
          ),
        ]);

      case _SendState.pickingDevice:
      case _SendState.fetchingCert:
        return null;
    }
  }

  Widget? _buildStatusLine(BuildContext context) {
    final device = _device;
    return switch (_state) {
      _SendState.idle when _filePaths.isNotEmpty && device != null =>
        StatusLine(
          message: '${device.name} must accept before any byte leaves '
              'this machine',
          live: false,
          color: Theme.of(context).colorScheme.primary,
        ),
      _SendState.sending => StatusLine(
          message: _isPaused
              ? 'Paused — the connection is held open'
              : 'Transferring directly, nothing is uploaded anywhere',
          color: _isPaused
              ? context.transferColors.declined
              : context.transferColors.success,
        ),
      _ => null,
    };
  }
}

/// A file in the queue: name, size, a hairline progress line, and a status
/// glyph. The current file takes an accent tint — selection is state.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.file,
    required this.isCurrent,
    required this.sending,
  });

  final BatchFile file;
  final bool isCurrent;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final success = context.transferColors.success;

    Widget trailing;
    if (file.isDone) {
      trailing = Icon(Icons.check_circle, size: 16, color: success);
    } else if (isCurrent) {
      trailing = Icon(Icons.arrow_downward, size: 16, color: scheme.primary);
    } else {
      trailing = Icon(Icons.circle_outlined,
          size: 14, color: scheme.onSurfaceVariant);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: isCurrent ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: isCurrent ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatBytes(file.bytes),
                style: text.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
          if (sending) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: file.progress,
                minHeight: 2,
                backgroundColor: scheme.outlineVariant,
                color: file.isDone ? success : scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
