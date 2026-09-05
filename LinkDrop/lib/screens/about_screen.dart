import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/update_checker.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';

/// What this build is, and whether a newer one has been released.
///
/// Check-and-notify only, on purpose (see [UpdateChecker]): the button never
/// downloads or installs anything by itself. A check that fails says so as a
/// failure — the one thing this screen must never do is report "you're up to
/// date" when it could not actually ask.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.manifestUrl});

  /// Overridden in tests and when pointing at a staging manifest.
  final String? manifestUrl;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String? _version;
  bool _checking = false;
  UpdateCheckResult? _result;
  String? _error;
  bool _copied = false;
  bool _disposed = false;

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    UpdateChecker.currentVersion(
      onError: (msg) => _safeSetState(() => _error = msg),
    ).then((v) => _safeSetState(() => _version = v));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _check() async {
    _safeSetState(() {
      _checking = true;
      _error = null;
      _result = null;
      _copied = false;
    });

    final result = await UpdateChecker.check(
      manifestUrl: widget.manifestUrl ?? UpdateChecker.defaultManifestUrl,
      currentVersionOverride: _version,
      onError: (msg) => _safeSetState(() => _error = msg),
    );

    _safeSetState(() {
      _checking = false;
      _result = result;
      // check() returning null without calling onError would leave the
      // screen silent, which reads as success. Never let that happen.
      if (result == null && _error == null) {
        _error = 'The update check did not complete, and did not say why.';
      }
    });
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    _safeSetState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _buildDetail(context);

    return LinkDropShell(
      title: 'About',
      // Nothing has been checked yet: one centred subject. The moment there
      // is a result or an error to read, the pane anchors to the top.
      centerContent: detail == null,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _buildIdentity(context),
      ),
      detail: detail,
      actions: _buildActions(context),
    );
  }

  Widget _buildIdentity(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('LinkDrop', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          _version == null ? 'Version unknown' : 'Version $_version',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Text(
          'Updates are published on GitHub. LinkDrop only checks and tells '
          'you — it never downloads or installs anything on its own.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget? _buildDetail(BuildContext context) {
    if (_error != null) return _buildError(context, _error!);
    final result = _result;
    if (result == null) return null;

    switch (result.outcome) {
      case UpdateOutcome.upToDate:
        return _buildPane(
          context,
          label: 'Up to date',
          headline: 'Version ${result.currentVersion} is the latest.',
          body: const [],
        );
      case UpdateOutcome.availableElsewhere:
        return _buildPane(
          context,
          label: 'Update available',
          headline: 'Version ${result.release.version} has been released.',
          body: [
            Text(
              'That release did not publish a build for this platform, so '
              'there is nothing to install yet.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (result.release.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _notes(context, result.release.notes),
            ],
          ],
        );
      case UpdateOutcome.available:
        return _buildPane(
          context,
          label: 'Update available',
          headline: 'Version ${result.release.version} is available.',
          body: [
            Text(
              'You are on ${result.currentVersion}. Download and install it '
              'yourself — LinkDrop will not replace itself.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (result.release.notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              _notes(context, result.release.notes),
            ],
            const SizedBox(height: 16),
            SelectableText(
              result.release.downloadUrl!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (UpdateChecker.canOpenDownload)
                  FilledButton.tonal(
                    onPressed: () => UpdateChecker.openDownload(
                      result.release.downloadUrl!,
                      onError: (msg) => _safeSetState(() => _error = msg),
                    ),
                    child: const Text('Open in browser'),
                  ),
                OutlinedButton(
                  onPressed: () => _copyLink(result.release.downloadUrl!),
                  child: Text(_copied ? 'Link copied' : 'Copy link'),
                ),
              ],
            ),
          ],
        );
    }
  }

  Widget _buildError(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Check failed'),
        const SizedBox(height: 12),
        Text(message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 16),
        Text(
          'This is not the same as being up to date — LinkDrop could not '
          'find out either way.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildPane(
    BuildContext context, {
    required String label,
    required String headline,
    required List<Widget> body,
  }) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label),
          const SizedBox(height: 12),
          Text(headline, style: theme.textTheme.titleMedium),
          if (body.isNotEmpty) const SizedBox(height: 12),
          ...body,
        ],
      ),
    );
  }

  Widget _notes(BuildContext context, String notes) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel("What's new"),
        const SizedBox(height: 8),
        Text(
          notes,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return FilledButton(
      onPressed: _checking ? null : _check,
      child: Text(_checking ? 'Checking...' : 'Check for updates'),
    );
  }
}
