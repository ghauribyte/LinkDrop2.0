import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:linkdrop/engine/update_checker.dart';

/// Exercises the update check against a real HTTP server on loopback, because
/// the outcomes that matter most are the failures: a check that cannot
/// complete must report *why*, and must never come back looking like
/// "you're up to date".
void main() {
  late HttpServer server;
  late String url;

  /// What the next request gets. Set per test.
  late Future<void> Function(HttpRequest) handler;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/latest.json';
    server.listen((request) async {
      await handler(request);
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  void serveJson(Map<String, dynamic> body) {
    handler = (request) async {
      request.response.write(jsonEncode(body));
    };
  }

  /// The asset key for the platform the test is running on, so these stay
  /// honest whether run on Linux or Android.
  final downloadKey = Platform.isAndroid ? 'android_url' : 'linux_url';

  Map<String, dynamic> manifest(String version, {bool withBuild = true}) => {
        'version': version,
        'tag': 'v$version',
        'notes': 'Notes for $version',
        if (withBuild) downloadKey: 'https://example.invalid/linkdrop.bin',
      };

  group('completed checks', () {
    test('the published version being the running one is up to date',
        () async {
      serveJson(manifest('0.1.0'));

      final result = await UpdateChecker.check(
        manifestUrl: url,
        currentVersionOverride: '0.1.0',
        onError: (m) => fail('unexpected error: $m'),
      );

      expect(result, isNotNull);
      expect(result!.outcome, UpdateOutcome.upToDate);
      expect(result.currentVersion, '0.1.0');
    });

    test('a newer version with a build for this platform is available',
        () async {
      serveJson(manifest('0.2.0'));

      final result = await UpdateChecker.check(
        manifestUrl: url,
        currentVersionOverride: '0.1.0',
        onError: (m) => fail('unexpected error: $m'),
      );

      expect(result!.outcome, UpdateOutcome.available);
      expect(result.release.version, '0.2.0');
      expect(result.release.notes, 'Notes for 0.2.0');
      expect(result.release.downloadUrl, isNotNull);
    });

    test('a newer version that published nothing for this platform is '
        'reported as such, not as an installable update', () async {
      serveJson(manifest('0.2.0', withBuild: false));

      final result = await UpdateChecker.check(
        manifestUrl: url,
        currentVersionOverride: '0.1.0',
        onError: (m) => fail('unexpected error: $m'),
      );

      expect(result!.outcome, UpdateOutcome.availableElsewhere);
      expect(result.release.downloadUrl, isNull);
    });

    test('a local build ahead of the published one is not nagged', () async {
      serveJson(manifest('0.1.0'));

      final result = await UpdateChecker.check(
        manifestUrl: url,
        currentVersionOverride: '0.9.0',
        onError: (m) => fail('unexpected error: $m'),
      );

      expect(result!.outcome, UpdateOutcome.upToDate);
    });
  });

  group('failed checks report the failure', () {
    /// Every case here must return null *and* say something. Returning null
    /// silently leaves the UI with nothing to show, which reads as success.
    Future<String> expectFailure(String manifestUrl) async {
      String? reported;
      final result = await UpdateChecker.check(
        manifestUrl: manifestUrl,
        currentVersionOverride: '0.1.0',
        onError: (m) => reported = m,
      );
      expect(result, isNull, reason: 'a failed check must not return a result');
      expect(reported, isNotNull, reason: 'a failed check must say why');
      return reported!;
    }

    test('a release published without its manifest', () async {
      handler = (request) async {
        request.response.statusCode = HttpStatus.notFound;
      };

      expect(await expectFailure(url), contains('manifest'));
    });

    test('any other HTTP status', () async {
      handler = (request) async {
        request.response.statusCode = HttpStatus.internalServerError;
      };

      expect(await expectFailure(url), contains('500'));
    });

    test('a truncated or otherwise unparseable body', () async {
      handler = (request) async {
        request.response.write('{"version": "0.2.0"');
      };

      await expectFailure(url);
    });

    test('valid JSON that is not an object', () async {
      handler = (request) async {
        request.response.write('["not", "a", "manifest"]');
      };

      await expectFailure(url);
    });

    test('an object with no version number', () async {
      serveJson({'tag': 'v0.2.0', 'notes': 'oops'});

      expect(await expectFailure(url), contains('version'));
    });

    test('nothing listening at all', () async {
      // Bind and immediately release a port so the connection is refused
      // rather than hanging on a black hole.
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadUrl = 'http://127.0.0.1:${dead.port}/latest.json';
      await dead.close(force: true);

      await expectFailure(deadUrl);
    });
  });

  group('version ordering', () {
    test('compares numerically, not as strings', () {
      // The case a lexicographic compare gets backwards.
      expect(UpdateChecker.isNewer('0.10.0', '0.9.0'), isTrue);
      expect(UpdateChecker.isNewer('0.9.0', '0.10.0'), isFalse);
    });

    test('equal versions are not newer', () {
      expect(UpdateChecker.isNewer('1.2.3', '1.2.3'), isFalse);
    });

    test('missing trailing segments count as zero', () {
      expect(UpdateChecker.isNewer('1.2', '1.2.0'), isFalse);
      expect(UpdateChecker.isNewer('1.2.1', '1.2'), isTrue);
    });

    test('a leading v and a +build suffix are tolerated', () {
      expect(UpdateChecker.isNewer('v0.2.0+7', '0.1.0+3'), isTrue);
    });

    test('an unparseable version never claims to be newer', () {
      expect(UpdateChecker.isNewer('not-a-version', '0.1.0'), isFalse);
      expect(UpdateChecker.isNewer('0.2.0', 'not-a-version'), isFalse);
    });
  });
}
