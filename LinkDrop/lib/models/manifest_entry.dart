/// Describes one file within a multi-file transfer manifest.
/// Sent as part of the manifest header before any file bytes (Decision 013).
class ManifestEntry {
  final String name;
  final int size;

  ManifestEntry({required this.name, required this.size});

  Map<String, dynamic> toJson() => {'name': name, 'size': size};

  factory ManifestEntry.fromJson(Map<String, dynamic> json) => ManifestEntry(
        name: json['name'] as String,
        size: json['size'] as int,
      );
}
