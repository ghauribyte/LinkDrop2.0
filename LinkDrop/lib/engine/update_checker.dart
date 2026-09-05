import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/update_info.dart';

/// What a completed check found.
enum UpdateOutcome {
  /// The running version is the published one, or newer (a local build).
  upToDate,

  /// A newer version is published. [UpdateCheckResult.release] describes it.
  available,

  /// A newer version exists but published nothing for this platform.
  availableElsewhere,
}

/// The result of a check that *completed*. A check that could not complete
/// returns null from [UpdateChecker.check] and reports why through `onError`
/// — the two must never be confused.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.outcome,
    required this.currentVersion,
    required this.release,
  });

  final UpdateOutcome outcome;
  final String currentVersion;
  final UpdateInfo release;
}

/// Asks GitHub whether a newer LinkDrop has been released.
///
/// UI-free per Decision 008: returns a result or null, reports failures
/// through [onError], and never throws to the caller.
///
/// Check-and-notify only. It deliberately does not download or install
/// anything: a sideloaded APK cannot replace itself without
/// REQUEST_INSTALL_PACKAGES and a FileProvider, and a Linux tarball has no
/// package manager to hand the work to. Claiming otherwise would be worse
/// than not offering it.
class UpdateChecker {
  /// GitHub redirects `releases/latest/download/<asset>` to whichever release
  /// is newest, so this URL never needs updating.
  ///
  /// Reading a release *asset* rather than the REST API on purpose: asset
  /// downloads are not subject to the API's unauthenticated rate limit, which
  /// is shared per source IP and so is easy to exhaust on a shared network.
  static const defaultManifestUrl =
      'https://github.com/ghauribyte/LinkDrop2.0/releases/latest/download/latest.json';

  /// A check should fail fast on a captive portal rather than hang the button.
  static const _timeout = Duration(seconds: 12);

  /// The version of the running build, e.g. `0.1.0`.
  ///
  /// Read from the installed package rather than a compiled-in constant, so
  /// it cannot drift from what the installer actually put on the device.
  static Future<String?> currentVersion({
    void Function(String message)? onError,
  }) async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      onError?.call('Could not read this build\'s version number: $e');
      return null;
    }
  }

  /// Returns null when the check could not be completed.
  ///
  /// Not reachable, blocked, a 404 from a release published without its
  /// manifest, a truncated body — all of these are errors, and reporting any
  /// of them as a confident "you're up to date" is the failure that makes an
  /// update feature look fine while it silently does nothing.
  static Future<UpdateCheckResult?> check({
    String manifestUrl = defaultManifestUrl,
    String? currentVersionOverride,
    void Function(String message)? onError,
  }) async {
    final current =
        currentVersionOverride ?? await currentVersion(onError: onError);
    if (current == null) return null;

    final body = await _fetch(manifestUrl, onError);
    if (body == null) return null;

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        onError?.call('The update manifest was not in the expected format.');
        return null;
      }
      json = decoded;
    } on FormatException {
      onError?.call('The update manifest could not be read. It may have '
          'been published incompletely — try again later.');
      return null;
    }

    final release = UpdateInfo.fromJson(json, _downloadKey);
    if (release == null) {
      onError?.call('The update manifest was missing a version number.');
      return null;
    }

    final UpdateOutcome outcome;
    if (!isNewer(release.version, current)) {
      outcome = UpdateOutcome.upToDate;
    } else if (release.downloadUrl == null) {
      outcome = UpdateOutcome.availableElsewhere;
    } else {
      outcome = UpdateOutcome.available;
    }

    return UpdateCheckResult(
      outcome: outcome,
      currentVersion: current,
      release: release,
    );
  }

  /// Whether [openDownload] can do anything on this platform.
  ///
  /// True on Linux, where `xdg-open` is already how the app hands files to
  /// the desktop (see [FileReveal]). False on Android: opening a URL there
  /// needs an Intent, which would mean a new platform channel or
  /// `url_launcher` — until then the screen offers the link to copy instead
  /// of a button that quietly does nothing.
  static bool get canOpenDownload => Platform.isLinux;

  /// Hands the download URL to the desktop's browser.
  static Future<bool> openDownload(
    String url, {
    void Function(String message)? onError,
  }) async {
    if (!canOpenDownload) return false;
    try {
      final result = await Process.run('xdg-open', [url]);
      if (result.exitCode != 0) {
        onError?.call('Could not open a browser. The link is above — copy it '
            'and open it yourself.');
        return false;
      }
      return true;
    } catch (e) {
      onError?.call('Could not open a browser: $e');
      return false;
    }
  }

  /// Which asset in the manifest this platform can actually install.
  static String get _downloadKey =>
      Platform.isAndroid ? 'android_url' : 'linux_url';

  static Future<String?> _fetch(
    String url,
    void Function(String message)? onError,
  ) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      // The manifest URL is a redirect by design; HttpClient follows it.
      final response = await request.close().timeout(_timeout);

      if (response.statusCode == 404) {
        // Specific because it has a specific cause worth naming: a release
        // exists but was published without its latest.json.
        await response.drain<void>();
        onError?.call('No update manifest was published with the latest '
            'release, so there is nothing to compare against.');
        return null;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        onError?.call('GitHub answered with ${response.statusCode}.');
        return null;
      }

      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } on TimeoutException {
      onError?.call('GitHub did not answer in time. Check the connection '
          'and try again.');
      return null;
    } on SocketException {
      // The distinction the reference pipeline insists on: this is "could
      // not ask", not "nothing new". Naming GitHub specifically matters
      // because a network that works fine can still block it.
      onError?.call('Could not reach github.com. This device may be offline, '
          'or on a network that blocks it.');
      return null;
    } on HandshakeException {
      onError?.call('The secure connection to github.com failed.');
      return null;
    } catch (e) {
      onError?.call('The update check failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// True when [candidate] is a later version than [current].
  ///
  /// Numeric segment-by-segment, so 0.10.0 beats 0.9.0 — a plain string
  /// comparison gets that backwards. Anything unparseable is treated as not
  /// newer: refusing to nag is the safe direction to be wrong in.
  static bool isNewer(String candidate, String current) {
    final a = _segments(candidate);
    final b = _segments(current);
    if (a == null || b == null) return false;

    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int>? _segments(String version) {
    // Tolerate a `+build` suffix and a leading `v` so this works on whatever
    // shape of version string it is handed.
    final core = version.trim().replaceFirst(RegExp(r'^v'), '').split('+').first;
    final parts = core.split('.');
    final out = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null) return null;
      out.add(n);
    }
    return out.isEmpty ? null : out;
  }
}
