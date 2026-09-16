// A patch source for the Shorebird updater that Dartvel serves itself.
//
// The updater in Shorebird's engine reads `base_url` from shorebird.yaml and
// asks `<base_url>/api/v1/patches/check`; everything else it needs is in the
// answer. The request and response shapes here are the updater's own
// (library/src/network.rs in shorebirdtech/updater): snake_case, a patch
// with number, hash, download_url and an optional hash_signature, and the
// numbers of patches that were rolled back.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> request({
  String appId = 'shopfront',
  String release = '1.0.0+1',
  String platform = 'android',
  String arch = 'x86_64',
  String channel = 'stable',
  int? current,
}) => <String, Object?>{
  'app_id': appId,
  'channel': channel,
  'release_version': release,
  'platform': platform,
  'arch': arch,
  'client_id': '6c1d-uuid',
  'current_patch_number': ?current,
};

void main() {
  late Directory root;
  late DVShorebirdPatchSource source;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_patch_source_');
    source = DVShorebirdPatchSource(root.path);
  });

  tearDown(() => root.deleteSync(recursive: true));

  DVShorebirdPatchTarget target({String arch = 'x86_64'}) =>
      DVShorebirdPatchTarget(
        appId: 'shopfront',
        releaseVersion: '1.0.0+1',
        platform: 'android',
        arch: arch,
      );

  test('a release with no patches offers nothing', () {
    final Map<String, Object?> answer = source.check(
      request(),
      downloadBase: Uri.parse('http://10.0.2.2:9090/updates'),
    );
    expect(answer['patch_available'], isFalse);
    expect(answer['patch'], isNull);
    expect(answer['rolled_back_patch_numbers'], isEmpty);
  });

  test('a published patch is offered with its hash and where to fetch it', () {
    final DVShorebirdPatch published = source.publish(
      target(),
      diff: <int>[40, 181, 47, 253, 1, 2, 3],
      patchedHash: 'ab' * 32,
    );
    expect(published.number, 1);

    final Map<String, Object?> answer = source.check(
      request(),
      downloadBase: Uri.parse('http://10.0.2.2:9090/updates'),
    );
    expect(answer['patch_available'], isTrue);
    final Map<String, Object?> patch = answer['patch']! as Map<String, Object?>;
    expect(patch['number'], 1);
    expect(patch['hash'], 'ab' * 32);
    expect(
      patch['download_url'],
      'http://10.0.2.2:9090/updates/patches/shopfront/1.0.0+1/android/x86_64/1',
    );
    expect(patch, isNot(contains('hash_signature')));
  });

  test('numbers rise per release and target, and the newest is offered', () {
    source.publish(target(), diff: <int>[1], patchedHash: 'a' * 64);
    final DVShorebirdPatch second = source.publish(
      target(),
      diff: <int>[2],
      patchedHash: 'b' * 64,
    );
    expect(second.number, 2);
    final Map<String, Object?> answer = source.check(
      request(),
      downloadBase: Uri.parse('http://h/u'),
    );
    expect((answer['patch']! as Map<String, Object?>)['number'], 2);
  });

  test('a device already running the newest patch is offered nothing', () {
    source.publish(target(), diff: <int>[1], patchedHash: 'a' * 64);
    final Map<String, Object?> answer = source.check(
      request(current: 1),
      downloadBase: Uri.parse('http://h/u'),
    );
    expect(answer['patch_available'], isFalse);
  });

  test('another release, platform, architecture or channel is not offered '
      'this patch', () {
    source.publish(target(), diff: <int>[1], patchedHash: 'a' * 64);
    for (final Map<String, Object?> other in <Map<String, Object?>>[
      request(release: '1.0.1+2'),
      request(platform: 'ios'),
      request(arch: 'aarch64'),
      request(channel: 'beta'),
      request(appId: 'another'),
    ]) {
      expect(
        source.check(other, downloadBase: Uri.parse('http://h/u'))['patch_available'],
        isFalse,
        reason: '$other',
      );
    }
  });

  test('a patch published to beta reaches beta only', () {
    source.publish(
      target(),
      diff: <int>[1],
      patchedHash: 'a' * 64,
      channel: 'beta',
    );
    expect(
      source.check(request(), downloadBase: Uri.parse('http://h/u'))['patch_available'],
      isFalse,
    );
    expect(
      source.check(
        request(channel: 'beta'),
        downloadBase: Uri.parse('http://h/u'),
      )['patch_available'],
      isTrue,
    );
  });

  test('a rolled-back patch is listed for devices to drop and never offered',
      () {
    source.publish(target(), diff: <int>[1], patchedHash: 'a' * 64);
    source.publish(target(), diff: <int>[2], patchedHash: 'b' * 64);
    source.rollBack(target(), 2);

    final Map<String, Object?> answer = source.check(
      request(current: 2),
      downloadBase: Uri.parse('http://h/u'),
    );
    expect(answer['rolled_back_patch_numbers'], <int>[2]);
    // Patch 1 is still good; a device on 2 is offered it back only if it is
    // newer than what it runs, which it is not, so it falls back to the
    // release until something newer ships.
    expect(answer['patch_available'], isFalse);

    final Map<String, Object?> fresh = source.check(
      request(),
      downloadBase: Uri.parse('http://h/u'),
    );
    expect((fresh['patch']! as Map<String, Object?>)['number'], 1);
  });

  test('rolling back a patch that does not exist is refused', () {
    expect(
      () => source.rollBack(target(), 7),
      throwsA(isA<StateError>()),
    );
  });

  test('a signature published with the patch is passed on', () {
    source.publish(
      target(),
      diff: <int>[1],
      patchedHash: 'a' * 64,
      hashSignature: 'c2lnbmF0dXJl',
    );
    final Map<String, Object?> answer = source.check(
      request(),
      downloadBase: Uri.parse('http://h/u'),
    );
    expect(
      (answer['patch']! as Map<String, Object?>)['hash_signature'],
      'c2lnbmF0dXJl',
    );
  });

  test('a path component that could escape the store is refused', () {
    expect(
      () => source.check(
        request(appId: '../../etc'),
        downloadBase: Uri.parse('http://h/u'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  group('over HTTP', () {
    late HttpServer server;
    late HttpClient client;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest req) async {
        if (!await source.handle(req, prefix: '/updates')) {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('check, then download the exact bytes published', () async {
      source.publish(
        target(),
        diff: <int>[40, 181, 47, 253, 9, 8, 7],
        patchedHash: 'ab' * 32,
      );
      final HttpClientRequest post = await client.postUrl(
        at('/updates/api/v1/patches/check'),
      );
      post.headers.contentType = ContentType.json;
      post.write(jsonEncode(request()));
      final HttpClientResponse checked = await post.close();
      expect(checked.statusCode, 200);
      final Map<String, Object?> answer =
          jsonDecode(await utf8.decodeStream(checked)) as Map<String, Object?>;
      final Uri download = Uri.parse(
        (answer['patch']! as Map<String, Object?>)['download_url']! as String,
      );
      // Built from the Host the device used, so it is reachable from there.
      expect(download.port, server.port);

      final HttpClientResponse fetched = await (await client.getUrl(
        download,
      )).close();
      expect(fetched.statusCode, 200);
      final List<int> bytes = await fetched.fold<List<int>>(
        <int>[],
        (List<int> all, List<int> chunk) => all..addAll(chunk),
      );
      expect(bytes, <int>[40, 181, 47, 253, 9, 8, 7]);
    });

    test('a resumed download gets the rest', () async {
      source.publish(target(), diff: <int>[0, 1, 2, 3, 4, 5], patchedHash: 'a' * 64);
      final HttpClientRequest get = await client.getUrl(
        at('/updates/patches/shopfront/1.0.0+1/android/x86_64/1'),
      );
      get.headers.set('range', 'bytes=4-');
      final HttpClientResponse response = await get.close();
      expect(response.statusCode, 206);
      expect(response.headers.value('content-range'), 'bytes 4-5/6');
      expect(await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b)), <int>[4, 5]);
    });

    test('events are accepted and nothing else under the prefix is', () async {
      final HttpClientRequest post = await client.postUrl(
        at('/updates/api/v1/patches/events'),
      );
      post.write('{"event":{"type":"__patch_install__"}}');
      expect((await post.close()).statusCode, 204);

      expect(
        (await (await client.getUrl(at('/updates/patches/../../x'))).close())
            .statusCode,
        anyOf(400, 404),
      );
    });
  });
}
