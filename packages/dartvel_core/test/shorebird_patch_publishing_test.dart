// Publishing into a patch source the application hosts, and serving it from
// the same server that serves the application.
//
// The web-server binary answers requests as dartvel_core Request and
// Response, not dart:io's HttpRequest, so the patch source has to answer in
// that shape too. Publishing is over the same address the updater checks,
// behind a token the server is started with; a server started without one
// publishes nothing, because a patch is code every device runs.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String url, {
  List<int> body = const <int>[],
  Map<String, String> headers = const <String, String>{},
}) {
  final Headers h = Headers();
  headers.forEach(h.set);
  return Request(
    method: method,
    url: Uri.parse(url),
    headers: h,
    bodyStream: Stream<List<int>>.value(body),
  );
}

Future<List<int>> _bytes(Response response) async => response.body == null
    ? <int>[]
    : await response.body!.stream.fold<List<int>>(
        <int>[],
        (List<int> all, List<int> chunk) => all..addAll(chunk),
      );

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(utf8.decode(await _bytes(response))) as Map<Object?, Object?>)
        .cast<String, Object?>();

const String _token = 'publish-token-0123456789abcdef';

String _publishUrl({
  String arch = 'x86_64',
  String hash = '',
  String channel = 'stable',
}) =>
    'https://updates.example.com/updates/_dartvel/publish'
    '?app_id=shopfront&release_version=1.0.0%2B1&platform=android'
    '&arch=$arch&hash=$hash&channel=$channel';

List<int> _check({int? current, String arch = 'x86_64'}) => utf8.encode(
  jsonEncode(<String, Object?>{
    'app_id': 'shopfront',
    'channel': 'stable',
    'release_version': '1.0.0+1',
    'platform': 'android',
    'arch': arch,
    'current_patch_number': ?current,
  }),
);

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_patch_publish_');
  });

  tearDown(() => root.deleteSync(recursive: true));

  final List<int> diff = <int>[40, 181, 47, 253, 7, 7, 7];
  final String patched = sha256.convert(<int>[1, 2, 3]).toString();

  test(
    'a published patch is checked for and downloaded as the updater does',
    () async {
      final DVShorebirdPatchSource source = DVShorebirdPatchSource(
        root.path,
        publishToken: _token,
      );

      final Response published = (await source.respond(
        _request(
          'POST',
          _publishUrl(hash: patched),
          body: diff,
          headers: <String, String>{'authorization': 'Bearer $_token'},
        ),
        prefix: '/updates',
      ))!;
      expect(published.status, 201);
      expect((await _json(published))['number'], 1);

      final Response checked = (await source.respond(
        _request(
          'POST',
          'https://updates.example.com/updates/api/v1/patches/check',
          body: _check(),
        ),
        prefix: '/updates',
      ))!;
      expect(checked.status, 200);
      final Map<String, Object?> answer = await _json(checked);
      expect(answer['patch_available'], isTrue);
      final Map<String, Object?> patch =
          answer['patch']! as Map<String, Object?>;
      expect(patch['hash'], patched);
      // The scheme and host the device reached, so a server behind TLS hands
      // out an https download the device can fetch.
      final Uri download = Uri.parse(patch['download_url']! as String);
      expect(download.scheme, 'https');
      expect(download.host, 'updates.example.com');

      final Response fetched = (await source.respond(
        _request('GET', download.toString()),
        prefix: '/updates',
      ))!;
      expect(fetched.status, 200);
      expect(await _bytes(fetched), diff);
    },
  );

  test('publishing without the token, or with another, is refused and stores '
      'nothing', () async {
    final DVShorebirdPatchSource source = DVShorebirdPatchSource(
      root.path,
      publishToken: _token,
    );
    for (final Map<String, String> headers in <Map<String, String>>[
      const <String, String>{},
      const <String, String>{'authorization': 'Bearer not-the-token'},
    ]) {
      final Response refused = (await source.respond(
        _request(
          'POST',
          _publishUrl(hash: patched),
          body: diff,
          headers: headers,
        ),
        prefix: '/updates',
      ))!;
      expect(refused.status, 401, reason: '$headers');
    }
    expect(
      source.patches(
        const DVShorebirdPatchTarget(
          appId: 'shopfront',
          releaseVersion: '1.0.0+1',
          platform: 'android',
          arch: 'x86_64',
        ),
      ),
      isEmpty,
    );
  });

  test(
    'a source started with no token publishes nothing, whatever is sent',
    () async {
      final DVShorebirdPatchSource source = DVShorebirdPatchSource(root.path);
      final Response refused = (await source.respond(
        _request(
          'POST',
          _publishUrl(hash: patched),
          body: diff,
          headers: const <String, String>{'authorization': 'Bearer '},
        ),
        prefix: '/updates',
      ))!;
      expect(refused.status, 403);
      expect(root.listSync(), isEmpty);
    },
  );

  test('a publish whose hash is not a SHA-256 is refused', () async {
    final DVShorebirdPatchSource source = DVShorebirdPatchSource(
      root.path,
      publishToken: _token,
    );
    final Response refused = (await source.respond(
      _request(
        'POST',
        _publishUrl(hash: 'nope'),
        body: diff,
        headers: <String, String>{'authorization': 'Bearer $_token'},
      ),
      prefix: '/updates',
    ))!;
    expect(refused.status, 400);
  });

  test(
    'rolling back over HTTP rolls back every architecture of the release',
    () async {
      final DVShorebirdPatchSource source = DVShorebirdPatchSource(
        root.path,
        publishToken: _token,
      );
      for (final String arch in <String>['aarch64', 'x86_64']) {
        await source.respond(
          _request(
            'POST',
            _publishUrl(arch: arch, hash: patched),
            body: diff,
            headers: <String, String>{'authorization': 'Bearer $_token'},
          ),
          prefix: '/updates',
        );
      }
      final Response rolled = (await source.respond(
        _request(
          'POST',
          'https://updates.example.com/updates/_dartvel/rollback',
          body: utf8.encode(
            jsonEncode(<String, Object?>{
              'app_id': 'shopfront',
              'release_version': '1.0.0+1',
              'platform': 'android',
              'number': 1,
            }),
          ),
          headers: <String, String>{'authorization': 'Bearer $_token'},
        ),
        prefix: '/updates',
      ))!;
      expect(rolled.status, 200);
      expect((await _json(rolled))['architectures'], <String>[
        'aarch64',
        'x86_64',
      ]);

      for (final String arch in <String>['aarch64', 'x86_64']) {
        final Map<String, Object?> answer = await _json(
          (await source.respond(
            _request(
              'POST',
              'https://updates.example.com/updates/api/v1/patches/check',
              body: _check(current: 1, arch: arch),
            ),
            prefix: '/updates',
          ))!,
        );
        expect(answer['patch_available'], isFalse, reason: arch);
        expect(answer['rolled_back_patch_numbers'], <int>[1], reason: arch);
      }
    },
  );

  test('rolling back without the token changes nothing', () async {
    final DVShorebirdPatchSource source = DVShorebirdPatchSource(
      root.path,
      publishToken: _token,
    );
    await source.respond(
      _request(
        'POST',
        _publishUrl(hash: patched),
        body: diff,
        headers: <String, String>{'authorization': 'Bearer $_token'},
      ),
      prefix: '/updates',
    );
    final Response refused = (await source.respond(
      _request(
        'POST',
        'https://updates.example.com/updates/_dartvel/rollback',
        body: utf8.encode(
          jsonEncode(<String, Object?>{
            'app_id': 'shopfront',
            'release_version': '1.0.0+1',
            'platform': 'android',
            'number': 1,
          }),
        ),
      ),
      prefix: '/updates',
    ))!;
    expect(refused.status, 401);
    final Map<String, Object?> answer = await _json(
      (await source.respond(
        _request(
          'POST',
          'https://updates.example.com/updates/api/v1/patches/check',
          body: _check(),
        ),
        prefix: '/updates',
      ))!,
    );
    expect(answer['patch_available'], isTrue);
  });

  test(
    'a request that is not the patch source is left for the application',
    () async {
      final DVShorebirdPatchSource source = DVShorebirdPatchSource(
        root.path,
        publishToken: _token,
      );
      for (final Request other in <Request>[
        _request('GET', 'https://updates.example.com/updates'),
        _request('GET', 'https://updates.example.com/'),
        _request(
          'GET',
          'https://updates.example.com/updates/patches/a/b/c/d/9',
        ),
        _request('POST', 'https://updates.example.com/api/v1/patches/check'),
      ]) {
        expect(
          await source.respond(other, prefix: '/updates'),
          isNull,
          reason: '${other.method} ${other.url}',
        );
      }
    },
  );
}
