import 'dart:io';

import 'package:flutter/material.dart';

import '../navigation/rail_scope.dart';

/// Layout breakpoints from the design spec (§04, "Killing the dead space").
///
/// The old build centred a min-height column in whatever window it was given,
/// which is what left the desktop looking mostly empty. The fix is structural,
/// not cosmetic: below [twoPane] a single scrolling column, above it a two-pane
/// split where the second pane always has something true to say — this device,
/// the queue, the selected peer, recents.
abstract final class Bp {
  /// Below this: phone layout. One column, 16dp gutters, actions docked to the
  /// bottom edge, touch targets 44-54dp.
  static const phone = 700.0;

  /// At or above this: rail + work pane + context pane.
  static const twoPane = 1100.0;

  /// Between [phone] and [twoPane] the rail is present but content stays a
  /// single column, stretched to this measure rather than a narrow strip.
  static const smallWindowContent = 720.0;

  /// Context pane width (spec says 360-420dp).
  static const detailPane = 392.0;

  /// Icon rail width.
  static const rail = 68.0;
}

/// The app's structural frame: rail + work pane + optional context pane.
///
/// [detail] must be real content for *this* screen. If a screen has nothing
/// legitimate to put there, pass null and let the content take the width —
/// never centre a narrow column in an empty window, which is the exact
/// problem this shell exists to remove.
class LinkDropShell extends StatelessWidget {
  const LinkDropShell({
    super.key,
    required this.title,
    required this.content,
    this.detail,
    this.detailOnLeft = false,
    this.detailWidth = Bp.detailPane,
    this.statusLine,
    this.actions,
    this.showBackOnPhone = true,
    this.centerContent = false,
  });

  /// Screen name, shown in the phone header and the desktop window strip.
  final String title;

  /// The work pane.
  final Widget content;

  /// The context pane. Null means this screen has nothing for it.
  final Widget? detail;

  /// Send puts its queue on the left; most screens put context on the right.
  final bool detailOnLeft;
  final double detailWidth;

  /// Single low-emphasis row pinned to the bottom of the pane (§03):
  /// a coloured dot for liveness plus plain text, no container.
  final Widget? statusLine;

  /// Docked to the bottom edge on phone, inline on desktop.
  final Widget? actions;

  final bool showBackOnPhone;

  /// Centre the content in the pane instead of anchoring it to the top.
  ///
  /// For waiting and empty states only — a screen with a list, a queue or a
  /// running transfer reads top-down and must stay top-anchored. Set from the
  /// screen's own state, not once per screen.
  final bool centerContent;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < Bp.phone) return _buildPhone(context);
    return _buildDesktop(context, width);
  }

  Widget _buildPhone(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        automaticallyImplyLeading: showBackOnPhone,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: ConstrainedBox(
                    // Same reasoning as desktop: the column gets the whole
                    // viewport so a waiting state can sit in the middle of
                    // the screen rather than under the app bar.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: centerContent && detail == null
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        content,
                        if (detail != null) ...[
                          const SizedBox(height: 20),
                          const Divider(height: 1),
                          const SizedBox(height: 16),
                          detail!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (statusLine != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: statusLine!,
              ),
            // Actions dock to the bottom edge on touch.
            if (actions != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: actions!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, double width) {
    final wide = width >= Bp.twoPane && detail != null;

    final work = Padding(
      padding: const EdgeInsets.fromLTRB(30, 24, 30, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: Align(
                  // A centred subject centres on both axes; otherwise the
                  // measure stays anchored to the left edge where a reading
                  // column belongs.
                  alignment:
                      centerContent ? Alignment.center : Alignment.topLeft,
                  child: ConstrainedBox(
                    // In the middle band there is no second pane, so the single
                    // column stretches to a real measure instead of hugging.
                    //
                    // minHeight hands the content the whole pane, which is what
                    // lets an idle screen centre its empty state rather than
                    // clinging to the top-left corner of an empty window.
                    // Content that starts at the top is unaffected.
                    constraints: BoxConstraints(
                      maxWidth: wide ? double.infinity : Bp.smallWindowContent,
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: centerContent
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      mainAxisAlignment: centerContent
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.start,
                      children: [
                        content,
                        // Inline on desktop, immediately under the thing it
                        // acts on. Pinning it to the pane's bottom edge left
                        // a form's submit button stranded hundreds of pixels
                        // below the last field.
                        if (actions != null) ...[
                          const SizedBox(height: 20),
                          actions!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (statusLine != null) ...[
            const SizedBox(height: 14),
            statusLine!,
          ],
        ],
      ),
    );

    final panes = <Widget>[
      if (wide && detailOnLeft) _detailPane(context),
      if (wide && detailOnLeft) const _PaneRule(),
      Expanded(child: work),
      if (wide && !detailOnLeft) const _PaneRule(),
      if (wide && !detailOnLeft) _detailPane(context),
    ];

    return Scaffold(
      body: Column(
        children: [
          // Window chrome spans the full width above the rail and both
          // panes, as in the design.
          _DesktopHeader(title: title),
          Expanded(
            child: Row(
              // Panes are full-height columns. Without stretch, Row centres
              // each child on its intrinsic height and the context pane
              // floats halfway down instead of starting level with the work
              // pane.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Rail(),
                const _PaneRule(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: panes,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailPane(BuildContext context) => SizedBox(
        width: detailWidth,
        // Top padding matches the work pane's header baseline so the two
        // columns start on the same line.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
          child: Align(
            alignment: Alignment.topLeft,
            child: detail,
          ),
        ),
      );
}

/// The window strip above the work pane: a back affordance when there is
/// somewhere to go back to, then "LinkDrop — Screen".
///
/// The rail replaces back-navigation *between destinations*, but a screen
/// pushed on top of one — the device picker, say — still needs a way out,
/// and on desktop there is no system back gesture to fall back on.
class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (canPop) ...[
            SizedBox(
              width: 30,
              height: 30,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Icon(Icons.arrow_back,
                      size: 17, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            'LinkDrop',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text('—',
              style: TextStyle(fontSize: 12, color: scheme.outlineVariant)),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 12, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _PaneRule extends StatelessWidget {
  const _PaneRule();

  @override
  Widget build(BuildContext context) => VerticalDivider(
        width: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

/// The 68dp icon rail. Replaces back-navigation above the phone breakpoint.
///
/// The selected item takes an accent tint plus a 1px accent edge (§03).
/// Renders as a bare strip if no [RailScope] is installed above it, so a
/// screen shown outside the app shell still lays out correctly.
class _Rail extends StatelessWidget {
  const _Rail();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final platformLabel = Platform.isAndroid ? 'ANDROID' : 'LINUX';
    final rail = RailScope.maybeOf(context);

    return Container(
      width: Bp.rail,
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          if (rail != null)
            for (var i = 0; i < rail.destinations.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _RailButton(
                  destination: rail.destinations[i],
                  selected: i == rail.currentIndex,
                  onTap: () => rail.onSelect(i),
                ),
              ),
          const Spacer(),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              platformLabel,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.04,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final RailDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: destination.label,
      preferBelow: false,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: selected
                ? BorderSide(color: scheme.primary, width: 1)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(
                destination.icon,
                size: 20,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
