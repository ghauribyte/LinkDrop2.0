/// Tracks progress of a single file transfer (send or receive).
class TransferProgress {
  final String filename;
  final int bytesDone;
  final int totalBytes;

  TransferProgress({
    required this.filename,
    required this.bytesDone,
    required this.totalBytes,
  });

  double get fraction => totalBytes == 0 ? 0 : bytesDone / totalBytes;
  bool get isComplete => bytesDone >= totalBytes;

  String get doneMB => (bytesDone / (1024 * 1024)).toStringAsFixed(2);
  String get totalMB => (totalBytes / (1024 * 1024)).toStringAsFixed(2);
}
