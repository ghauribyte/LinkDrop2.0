/// Tracks progress of a single file transfer (send or receive).
///
/// [fileIndex] and [fileCount] are optional — they describe this
/// file's position within a multi-file batch (Decision 013). For a
/// single-file send/receive, both default to 1, so existing CLI code
/// and any code that doesn't care about batches needs no changes.
class TransferProgress {
  final String filename;
  final int bytesDone;
  final int totalBytes;
  final int fileIndex;
  final int fileCount;

  TransferProgress({
    required this.filename,
    required this.bytesDone,
    required this.totalBytes,
    this.fileIndex = 1,
    this.fileCount = 1,
  });

  double get fraction => totalBytes == 0 ? 0 : bytesDone / totalBytes;
  bool get isComplete => bytesDone >= totalBytes;
  bool get isBatch => fileCount > 1;

  String get doneMB => (bytesDone / (1024 * 1024)).toStringAsFixed(2);
  String get totalMB => (totalBytes / (1024 * 1024)).toStringAsFixed(2);

  /// e.g. "2 of 5" — only meaningful when isBatch is true.
  String get batchLabel => '$fileIndex of $fileCount';
}
