import 'dart:io';

import 'package:flutter/material.dart';

import '../services/receiver_service.dart';
import '../theme/linkdrop_theme.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import '../widgets/transfer_progress_view.dart';

/// The receiving side of LinkDrop, as a *view* over [ReceiverService].
///
/// The sockets deliberately do not belong to this screen. They used to: the
/// State owned the FileReceiver and DiscoveryBroadcaster and stopped both in
/// dispose(), so leaving the screen closed the listening port while the app
/// kept running, and a sender that had already discovered this device got a
/// bare "Connection refused". Listening is now app-level state the user turns
/// on and off explicitly, and navigating away changes nothing.
///
/// What remains here is presentation plus two controls: start listening, and
/// stop listening.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  ReceiverService get _service => ReceiverService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    // Opening this screen is still the natural "I want to receive" gesture,
    // so it starts listening — but unlike before, closing it does not stop.
    _service.ensureStarted();
  }

  @override
  void dispose() {
    // Detach only. Stopping here is precisely the bug this screen no longer
    // has: the service outlives the widget on purpose.
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LinkDropShell(
      title: 'Receive',
      // Waiting is a single centred subject; a live or finished transfer is a
      // list of files and reads from the top.
      centerContent: _service.state == ReceiveState.idle,
      content: _buildContent(context),
      detail: _buildDetail(context),
      statusLine: _buildStatusLine(context),
      actions: _buildActions(context),
    );
  }

  Widget? _buildActions(BuildContext context) {
    // Never offer to tear down the sockets mid-transfer.
    if (_service.state == ReceiveState.receiving) return null;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (_service.isListening)
          OutlinedButton.icon(
            onPressed: () => _service.stop(),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Stop listening'),
          )
        else
          FilledButton.icon(
            onPressed: () => _service.ensureStarted(),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Start listening'),
          ),
        if (_service.state == ReceiveState.complete ||
            _service.state == ReceiveState.declined ||
            _service.state == ReceiveState.failed)
          TextButton(
            onPressed: () => _service.acknowledgeOutcome(),
            child: const Text('Dismiss'),
          ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final identity = _service.identity;
    final incoming = _service.incoming;

    switch (_service.state) {
      case ReceiveState.receiving:
        final progress = _service.progress;
        if (progress == null) break;

        final total = incoming.fold<int>(0, (sum, f) => sum + f.size);
        final currentIndex = progress.fileIndex - 1;
        var done = 0;
        for (var i = 0; i < currentIndex && i < incoming.length; i++) {
          done += incoming[i].size;
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
              rate: _service.meter.rateLabel,
              eta: _service.meter.etaLabel(total - done),
            ),
            const SizedBox(height: 18),
            BatchProgressBar(
              files: [
                for (var i = 0; i < incoming.length; i++)
                  BatchFile(
                    name: incoming[i].name,
                    bytes: incoming[i].size,
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

      case ReceiveState.complete:
        return _outcome(
          context,
          icon: Icons.check_circle_outline,
          color: context.transferColors.success,
          title: 'Transfer complete',
          detail: _service.statusMessage ?? 'All files received.',
        );

      case ReceiveState.declined:
        return _outcome(
          context,
          icon: Icons.remove_circle_outline,
          color: context.transferColors.declined,
          title: 'Transfer declined',
          detail: _service.statusMessage ??
              'Nothing was written to disk. Still listening.',
        );

      case ReceiveState.failed:
        return _outcome(
          context,
          icon: Icons.error_outline,
          color: scheme.error,
          title: 'Something went wrong',
          detail: _service.errorMessage ?? 'The transfer could not complete.',
        );

      case ReceiveState.idle:
        break;
    }

    // Idle: either listening and waiting, or stopped and offering to start.
    if (!_service.isListening) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.pause_circle_outline,
              size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 18),
          Text('Not listening', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'This device will not appear to senders and cannot receive '
            'files until you start listening.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    final address = identity?.ipAddress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PulseEmptyState(
          icon: Icons.download_outlined,
          title: 'Waiting for incoming files',
          subtitle: address == null
              ? 'You will be asked before anything is written to disk.'
              : 'This device is listening on $address. You will be asked '
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
    final recents = _service.recents;

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
                    _service.receivedDir?.path ?? '…',
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
          if (recents.isEmpty)
            Text(
              'Nothing received yet this session.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            for (final entry in recents.take(8))
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
    if (_service.state == ReceiveState.failed) {
      return StatusLine(
        message: _service.errorMessage ?? 'Receiver stopped',
        live: false,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (!_service.isListening) {
      return const StatusLine(
        message: 'Not listening — this device is invisible to senders',
        live: false,
      );
    }
    final address = _service.identity?.ipAddress;
    if (address == null) return null;
    return StatusLine(
      message: Platform.isAndroid
          ? 'Listening on $address — stays active if you switch screens'
          : 'Listening on $address',
      // A profile on a Pixel 7 put ~32% of samples under drawFrame during an
      // active receive, almost all of it StatusDot's unconditional 60fps
      // AnimationController — UI painting and the transfer's socket
      // callbacks share the same isolate's event loop, so a continuous
      // animation is a direct competitor for turns on it, not free chrome.
      // The blink communicates "listening"; once bytes are actually moving
      // the progress bar already says that more directly, so the dot goes
      // static rather than keep ticking through the whole transfer.
      live: _service.state != ReceiveState.receiving,
    );
  }
}
