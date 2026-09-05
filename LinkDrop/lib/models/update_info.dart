/// A published release, as described by the `latest.json` asset the release
/// workflow attaches to every GitHub Release.
///
/// Deliberately not "the newest release" — [UpdateChecker] decides whether
/// this is newer than what is running. This is just what the manifest said.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.downloadUrl,
  });

  /// Parses the manifest body. Returns null on anything malformed — a
  /// truncated download or a hand-created release with no real assets must
  /// read as "could not check", never as "you are up to date".
  ///
  /// [downloadKey] selects the asset for the running platform, so the model
  /// stays free of `Platform` checks.
  static UpdateInfo? fromJson(Map<String, dynamic> json, String downloadKey) {
    final version = json['version'];
    final tag = json['tag'];
    if (version is! String || version.isEmpty) return null;
    if (tag is! String || tag.isEmpty) return null;

    final url = json[downloadKey];
    final notes = json['notes'];

    return UpdateInfo(
      version: version,
      tag: tag,
      notes: notes is String ? notes.trim() : '',
      // A release with no build for this platform is a real, expected state
      // (one OS's build failed, or a release predates that platform), so it
      // is null rather than a parse failure.
      downloadUrl: url is String && url.isNotEmpty ? url : null,
    );
  }

  /// The `x.y.z` from pubspec, without the `+build` suffix.
  final String version;

  /// The git tag the release was cut from, e.g. `v0.2.0`.
  final String tag;

  /// The annotated tag's message. This project keeps no CHANGELOG file, so
  /// the tag message is the release notes. May be empty.
  final String notes;

  /// Where to get the build for the running platform, or null if this
  /// release published nothing for it.
  final String? downloadUrl;
}
