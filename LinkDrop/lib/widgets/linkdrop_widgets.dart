import 'package:flutter/material.dart';

import '../theme/linkdrop_theme.dart';

/// 64dp device row (§03): platform icon, name at 16, IP and freshness at 12,
/// a platform tag, and a chevron.
///
/// Selection is *state*, not navigation: the selected row takes an accent
/// tint plus a 1px accent edge rather than looking like a pressed link.
class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.name,
    required this.subtitle,
    this.tag,
    this.isPhone = false,
    this.selected = false,
    this.onTap,
  });

  final String name;

  /// e.g. "192.168.1.31 · seen 2 s ago".
  final String subtitle;

  /// e.g. "phone" / "linux".
  final String? tag;

  /// Chooses the platform glyph.
  final bool isPhone;

  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isPhone ? Icons.smartphone_outlined : Icons.laptop_outlined,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: 10),
                _Tag(tag!),
              ],
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: scheme.surfaceContainer,
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Concentric pulsing rings with a glyph at the centre.
///
/// Empty states animate because they mean work in progress — the app is
/// listening or scanning, not stuck.
class PulseTarget extends StatefulWidget {
  const PulseTarget({
    super.key,
    required this.icon,
    this.size = 132,
    this.rings = 3,
    this.period = const Duration(milliseconds: 2800),
    this.color,
    this.iconSize = 38,
  });

  final IconData icon;
  final double size;
  final int rings;
  final Duration period;

  /// Accent when the app is working for you; pass a neutral when it is
  /// looking for something that may not exist.
  final Color? color;
  final double iconSize;

  @override
  State<PulseTarget> createState() => _PulseTargetState();
}

class _PulseTargetState extends State<PulseTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < widget.rings; i++) _ring(i, color),
            Icon(widget.icon, size: widget.iconSize, color: color),
          ],
        ),
      ),
    );
  }

  Widget _ring(int index, Color color) {
    final seconds = widget.period.inMilliseconds / 1000;
    final offset = (index * 0.9) / seconds;
    final raw = (_controller.value + offset) % 1.0;
    final eased = Curves.easeOut.transform(raw);
    final scale = 0.35 + 0.65 * eased;
    final opacity = raw >= 0.7 ? 0.0 : 0.55 * (1 - raw / 0.7);

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1),
          ),
        ),
      ),
    );
  }
}

/// A blinking liveness dot.
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    this.color,
    this.size = 7,
    this.period = const Duration(milliseconds: 2400),
  });

  final Color? color;
  final double size;
  final Duration period;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)
        ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.transferColors.success;
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.25).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// The status line (§03): a single 11-12px row pinned to the bottom of the
/// pane — a coloured dot for liveness, plain text, no container.
class StatusLine extends StatelessWidget {
  const StatusLine(
      {super.key, required this.message, this.color, this.live = true});

  final String message;
  final Color? color;

  /// False renders a static dot — for a resting or finished state.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = color ?? context.transferColors.success;

    return Row(
      children: [
        if (live)
          StatusDot(color: dotColor, size: 6)
        else
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Centred empty state: pulse target, headline, and a supporting line.
class PulseEmptyState extends StatelessWidget {
  const PulseEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // A waiting state is one centred subject, not a column of records: the
    // ring, the headline and the explanation share an axis. Width is capped
    // so the subtitle wraps into a readable block instead of running the
    // full span of a wide pane.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PulseTarget(icon: icon, color: color),
            const SizedBox(height: 22),
            Text(title,
                style: text.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section label (§02): 13/w500/+8% tracking, upper case.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}

/// Monospace fingerprint (§02) — accent colour, never body-weight accent.
class FingerprintText extends StatelessWidget {
  const FingerprintText(this.fingerprint, {super.key, this.note});

  final String fingerprint;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.fingerprint, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          fingerprint,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: scheme.primary,
          ),
        ),
        if (note != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note!,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}
