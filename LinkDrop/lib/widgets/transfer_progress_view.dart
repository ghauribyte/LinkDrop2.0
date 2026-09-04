import 'package:flutter/material.dart';

import '../theme/linkdrop_theme.dart';
import 'linkdrop_shell.dart';

/// One file's slice of a batch transfer.
class BatchFile {
  const BatchFile({
    required this.name,
    required this.bytes,
    required this.progress,
  });

  final String name;
  final int bytes;

  /// 0..1 for this file alone.
  final double progress;

  bool get isDone => progress >= 1.0;
}

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}

/// The batch bar: one segment per file, each weighted by that file's byte
/// size, so batch position is visible without reading it — green behind,
/// accent moving, neutral ahead.
///
/// This is the component a stock [LinearProgressIndicator] cannot express,
/// and it replaces it entirely on the transfer screens.
class BatchProgressBar extends StatelessWidget {
  const BatchProgressBar({
    super.key,
    required this.files,
    this.height = 10,
    this.gap = 4,
  });

  final List<BatchFile> files;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final success = context.transferColors.success;

    if (files.isEmpty) {
      return SizedBox(
        height: height,
        child: _Segment(
          progress: 0,
          fill: scheme.primary,
          track: scheme.outlineVariant,
        ),
      );
    }

    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < files.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              // The flex IS the file size — that is the whole point of the
              // component. A 200 MB video must look like more of the batch
              // than a 0.1 MB note.
              flex: files[i].bytes.clamp(1, 1 << 30),
              child: _Segment(
                progress: files[i].progress,
                fill: files[i].isDone ? success : scheme.primary,
                track: scheme.outlineVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.progress,
    required this.fill,
    required this.track,
  });

  final double progress;
  final Color fill;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: ColoredBox(
        color: track,
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The numeral + metadata block above the bar.
///
/// The percentage carries the display role because it is the thing people
/// actually watch; rate and ETA sit right-aligned as metadata.
class TransferHeadline extends StatelessWidget {
  const TransferHeadline({
    super.key,
    required this.percent,
    required this.currentName,
    required this.fileIndex,
    required this.fileCount,
    required this.doneLabel,
    required this.totalLabel,
    required this.stateWord,
    this.rate,
    this.eta,
    this.paused = false,
  });

  /// 0..1 across the whole batch.
  final double percent;
  final String currentName;
  final int fileIndex;
  final int fileCount;
  final String doneLabel;
  final String totalLabel;

  /// "Sending" / "Receiving" / "Paused".
  final String stateWord;

  /// e.g. "7.3 MB/s". Null hides the rate — the engine does not measure
  /// throughput yet, so this is optional rather than faked.
  final String? rate;

  /// e.g. "19 s left". Null hides it, same reason as [rate].
  final String? eta;

  final bool paused;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isPhone = MediaQuery.sizeOf(context).width < Bp.phone;

    final stateColor =
        paused ? context.transferColors.declined : scheme.primary;
    final pct = '${(percent.clamp(0.0, 1.0) * 100).round()}%';

    // 96 on desktop, 64 on phone (§02).
    final numeral = text.displaySmall?.copyWith(fontSize: isPhone ? 64 : 96);

    final rateEta = [
      if (rate != null) rate!,
      if (eta != null) eta!,
    ].join(' · ');

    if (isPhone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pct, style: numeral),
          const SizedBox(height: 6),
          Text(
            rate == null ? stateWord : '$stateWord · $rate',
            style: text.bodyMedium?.copyWith(color: stateColor),
          ),
          Text(
            '$doneLabel of $totalLabel${eta == null ? '' : ' · $eta'}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(pct, style: numeral),
        const SizedBox(width: 18),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
                Text(
                  'File $fileIndex of $fileCount · $doneLabel of $totalLabel',
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(stateWord,
                  style: text.bodyMedium?.copyWith(color: stateColor)),
              if (rateEta.isNotEmpty)
                Text(rateEta,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
