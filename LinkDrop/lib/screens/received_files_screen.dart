import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/file_reveal.dart';
import '../engine/received_log.dart';
import '../widgets/linkdrop_shell.dart';
import '../widgets/linkdrop_widgets.dart';
import '../widgets/transfer_progress_view.dart';

/// Everything this device has received, across sessions.
///
/// The receive screen keeps a list for the current session, but that dies
/// with the screen — and "where did that file actually go?" is a question
/// people ask *later*, which is exactly when the session list is gone. This
/// reads the persisted log instead.
///
/// Tapping a row opens the file: the gallery or a viewer on Android, the
/// default application on Linux. The folder button reveals it in the file
/// manager with the file selected, for when the answer needed is "where",
/// not "what".
class ReceivedFilesScreen extends StatefulWidget {
  const ReceivedFilesScreen({super.key});

  @override
  State<ReceivedFilesScreen> createState() => _ReceivedFilesScreenState();
}

class _ReceivedFilesScreenState extends State<ReceivedFilesScreen> {
  List<ReceivedFile> _entries = [];
  bool _loading = true;
  String? _error;
  String? _notice;
  Directory? _dir;
  bool _disposed = false;

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    _safeSetState(() => _loading = true);

    final Directory docsDir;
    try {
      docsDir = await getApplicationDocumentsDirectory();
    } catch (e) {
      _safeSetState(() {
        _loading = false;
        _error = 'Could not read the received-files history: $e';
      });
      return;
    }

    final dir = Directory('${docsDir.path}/linkdrop');
    final entries = await ReceivedLog(directory: dir).load();

    _safeSetState(() {
      _dir = dir;
      _entries = entries;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _open(ReceivedFile entry) async {
    final ok = await FileReveal.open(
      path: entry.path,
      contentUri: entry.contentUri,
      onError: (msg) => _safeSetState(() => _notice = msg),
    );
    if (ok) _safeSetState(() => _notice = null);
  }

  Future<void> _reveal(ReceivedFile entry) async {
    final ok = await FileReveal.revealInFolder(
      path: entry.path,
      contentUri: entry.contentUri,
      onError: (msg) => _safeSetState(() => _notice = msg),
    );
    if (ok) _safeSetState(() => _notice = null);
  }

  Future<void> _clear() async {
    final dir = _dir;
    if (dir == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear this list?'),
            content: const Text(
              'This only clears the history shown here. The files themselves '
              'are not deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    await ReceivedLog(directory: dir).clear();
    _safeSetState(() => _entries = []);
  }

  @override
  Widget build(BuildContext context) {
    return LinkDropShell(
      title: 'Received files',
      // Loading is a single centred subject too — a spinner pinned under
      // the header of an otherwise empty pane reads as a stuck screen.
      centerContent: _loading || _entries.isEmpty,
      content: _buildContent(context),
      detail: _entries.isEmpty ? null : _buildDetail(context),
      statusLine: _buildStatusLine(context),
      actions: _entries.isEmpty ? null : _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 38, color: scheme.error),
          const SizedBox(height: 18),
          Text('Could not load history', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    if (_entries.isEmpty) {
      return const PulseEmptyState(
        icon: Icons.inbox_outlined,
        title: 'Nothing received yet',
        subtitle: 'Files sent to this device will be listed here, with a way '
            'to open each one where it landed.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Received files', style: text.headlineMedium),
        const SizedBox(height: 10),
        Text(
          'Tap a file to open it. Newest first.',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        for (final entry in _entries)
          _ReceivedRow(
            entry: entry,
            onOpen: () => _open(entry),
            onReveal: () => _reveal(entry),
          ),
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = _entries.fold<int>(0, (sum, e) => sum + e.bytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Where files land'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Platform.isAndroid ? 'Gallery and Downloads' : 'Received folder',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                Platform.isAndroid
                    ? 'Photos and video are published to the gallery under '
                        'LinkDrop; anything else goes to Downloads.'
                    : '${_dir?.path ?? ''}/received',
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: Platform.isAndroid ? null : 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionLabel('This history'),
        const SizedBox(height: 10),
        Text(
          '${_entries.length} file${_entries.length == 1 ? '' : 's'} · '
          '${formatBytes(total)}',
          style: text.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
        const SizedBox(width: 10),
        TextButton.icon(
          onPressed: _clear,
          icon: const Icon(Icons.clear_all, size: 18),
          label: const Text('Clear list'),
        ),
      ],
    );
  }

  Widget? _buildStatusLine(BuildContext context) {
    final notice = _notice;
    if (notice != null) {
      return StatusLine(
        message: notice,
        live: false,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (_entries.isEmpty) return null;
    return const StatusLine(
      message: 'Clearing this list never deletes the files themselves',
      live: false,
    );
  }
}

/// One received file: name, size and when it arrived, then a way to open it
/// and a way to find it.
class _ReceivedRow extends StatelessWidget {
  const _ReceivedRow({
    required this.entry,
    required this.onOpen,
    required this.onReveal,
  });

  final ReceivedFile entry;
  final VoidCallback onOpen;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(_iconFor(entry.name), size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatBytes(entry.bytes)} · ${_when(entry.receivedAt)}',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onReveal,
                icon: const Icon(Icons.folder_open_outlined, size: 19),
                tooltip: Platform.isAndroid
                    ? 'Open'
                    : 'Show in file manager',
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};
    const videos = {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v'};
    const audio = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'};
    if (images.contains(ext)) return Icons.image_outlined;
    if (videos.contains(ext)) return Icons.movie_outlined;
    if (audio.contains(ext)) return Icons.audiotrack_outlined;
    if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  /// Relative for anything recent, absolute once "3 days ago" stops being
  /// more useful than the actual date.
  static String _when(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }
}
