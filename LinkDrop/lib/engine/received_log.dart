import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One file this device has received.
class ReceivedFile {
  ReceivedFile({
    required this.name,
    required this.path,
    required this.bytes,
    required this.receivedAt,
    this.contentUri,
  });

  final String name;

  /// Where the file lives on disk. On Android this is the app-private
  /// staging path, which stops existing once the file is exported to the
  /// gallery — [contentUri] is the durable handle there.
  final String path;

  final int bytes;
  final DateTime receivedAt;

  /// Android MediaStore `content://` URI, set once the file is published to
  /// the gallery. Null on Linux, and null on Android if the export failed.
  final String? contentUri;

  ReceivedFile copyWith({String? contentUri}) => ReceivedFile(
        name: name,
        path: path,
        bytes: bytes,
        receivedAt: receivedAt,
        contentUri: contentUri ?? this.contentUri,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'bytes': bytes,
        'receivedAt': receivedAt.toIso8601String(),
        if (contentUri != null) 'contentUri': contentUri,
      };

  /// Returns null rather than throwing on a malformed entry, so one bad
  /// record cannot make the whole history unreadable.
  static ReceivedFile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final path = raw['path'];
    final bytes = raw['bytes'];
    final receivedAt = raw['receivedAt'];
    if (name is! String || path is! String) return null;

    return ReceivedFile(
      name: name,
      path: path,
      bytes: bytes is int ? bytes : 0,
      receivedAt: receivedAt is String
          ? (DateTime.tryParse(receivedAt) ?? DateTime.now())
          : DateTime.now(),
      contentUri: raw['contentUri'] is String ? raw['contentUri'] as String : null,
    );
  }
}

/// A persisted list of everything this device has received.
///
/// The receive screen already kept a session list, but it died with the
/// screen — so "where did that file go?" had no answer after a restart,
/// which is the moment people actually ask. This is a small append-only
/// JSON log next to the received files themselves.
///
/// UI-free per Decision 008: no widgets, failures swallowed rather than
/// thrown, since a broken history must never take down a transfer.
class ReceivedLog {
  ReceivedLog({required this.directory});

  /// The `linkdrop/` app directory — the log sits beside `received/`.
  final Directory directory;

  static const _fileName = 'received_log.json';

  /// Cap on retained entries. The history is a convenience, not an archive,
  /// and an unbounded JSON file rewritten on every received file would get
  /// slower with every transfer.
  static const _maxEntries = 500;

  File get _file => File('${directory.path}/$_fileName');

  Future<List<ReceivedFile>> load() async {
    try {
      final file = _file;
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return raw
          .map(ReceivedFile.fromJson)
          .whereType<ReceivedFile>()
          .toList();
    } catch (_) {
      // A corrupt log reads as an empty history rather than an error.
      return [];
    }
  }

  Future<void> add(ReceivedFile entry) async {
    final entries = await load();
    entries.insert(0, entry);
    await _write(entries.take(_maxEntries).toList());
  }

  /// Records the gallery URI for an already-logged file, matched on the
  /// staging path — the export happens after the entry is written.
  Future<void> setContentUri({
    required String path,
    required String contentUri,
  }) async {
    final entries = await load();
    var changed = false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].path == path && entries[i].contentUri == null) {
        entries[i] = entries[i].copyWith(contentUri: contentUri);
        changed = true;
        break;
      }
    }
    if (changed) await _write(entries);
  }

  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {
      // Nothing actionable.
    }
  }

  Future<void> _write(List<ReceivedFile> entries) async {
    try {
      await directory.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Losing the history is not worth surfacing as a transfer failure.
    }
  }
}
