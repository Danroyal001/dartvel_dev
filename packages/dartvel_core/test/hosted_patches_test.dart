// What a patch source needs to be hosted for other people: staged rollout,
// signed releases, and install counting with a hook for billing.
//
// The silent failures this guards:
//
//  * a staged rollout drawn at random, which offers a device a patch at one
//    check and withdraws it at the next;
//  * a rollout that is raised and drops devices that already had it;
//  * a signed release accepting a patch whose signature every device will
//    refuse -- published, counted as shipped, and booted by nobody;
//  * a device that reports the same install twice billed twice, and a failed
//    install billed at all;
//  * installs counted into the wrong month.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _token = 'hosted-token-0123456789abcdef';

Request _request(
  String method,
  String path, {
  Object? json,
  List<int>? body,
  bool authorized = false,
}) {
  final Headers headers = Headers();
  if (authorized) headers.set('authorization', 'Bearer $_token');
  return Request(
    method: method,
    url: Uri.parse('https://cloud.example.test/updates$path'),
    headers: headers,
    bodyStream: Stream<List<int>>.value(
      body ?? (json == null ? <int>[] : utf8.encode(jsonEncode(json))),
    ),
  );
}

Future<String> _text(Response response) async => response.body == null
    ? ''
    : utf8.decode(
        await response.body!.stream.fold<List<int>>(
          <int>[],
          (List<int> all, List<int> chunk) => all..addAll(chunk),
        ),
      );

Map<String, Object?> _ask(
  String client, {
  int? current,
  String arch = 'aarch64',
}) => <String, Object?>{
  'app_id': 'shop',
  'channel': 'stable',
  'release_version': '1.0.0+1',
  'platform': 'ios',
  'arch': arch,
  'client_id': client,
  'current_patch_number': ?current,
};

Map<String, Object?> _event(
  String client,
  int number, {
  String type = '__patch_install__',
  int timestamp = 1791504000, // 2026-10-09T00:00:00Z
}) => <String, Object?>{
  'event': <String, Object?>{
    'app_id': 'shop',
    'arch': 'aarch64',
    'client_id': client,
    'type': type,
    'patch_number': number,
    'platform': 'ios',
    'release_version': '1.0.0+1',
    'timestamp': timestamp,
    'message': null,
  },
};

void main() {
  late Directory root;
  late DateTime now;
  late List<DVShorebirdPatchInstall> hooked;
  late DVShorebirdPatchSource source;
  bool offering = true;

  const DVShorebirdPatchTarget target = DVShorebirdPatchTarget(
    appId: 'shop',
    releaseVersion: '1.0.0+1',
    platform: 'ios',
    arch: 'aarch64',
  );
  final Uri base = Uri.parse('https://cloud.example.test/updates');
  String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_hosted_patches_');
    now = DateTime.utc(2026, 10, 9, 12);
    hooked = <DVShorebirdPatchInstall>[];
    offering = true;
    source = DVShorebirdPatchSource(
      root.path,
      publishToken: _token,
      clock: () => now,
      onInstall: hooked.add,
      mayOffer: (DVShorebirdPatchTarget t) => offering,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('staged rollout', () {
    final List<String> fleet = <String>[
      for (int i = 0; i < 1000; i++) 'client-$i',
    ];

    Set<String> offered() => <String>{
      for (final String client in fleet)
        if (source.check(_ask(client), downloadBase: base)['patch_available'] ==
            true)
          client,
    };

    test('reaches about the share asked for, the same devices every time, '
        'and keeps them as it grows', () {
      source.publish(
        target,
        diff: <int>[1],
        patchedHash: hashOf('one'),
        rolloutPercent: 30,
      );
      final Set<String> first = offered();
      expect(first.length, inInclusiveRange(240, 360));
      expect(offered(), first, reason: 'the same devices at every check');

      source.rolloutRelease(
        appId: 'shop',
        releaseVersion: '1.0.0+1',
        platform: 'ios',
        number: 1,
        percent: 60,
      );
      final Set<String> grown = offered();
      expect(grown.length, inInclusiveRange(520, 680));
      expect(
        grown.containsAll(first),
        isTrue,
        reason: 'raising a rollout must not drop a device it reached',
      );

      source.rolloutRelease(
        appId: 'shop',
        releaseVersion: '1.0.0+1',
        platform: 'ios',
        number: 1,
        percent: 100,
      );
      expect(offered().length, fleet.length);
    });

    test('a device outside a new patch\'s rollout is still offered the last '
        'patch it is inside', () {
      source.publish(target, diff: <int>[1], patchedHash: hashOf('one'));
      source.publish(
        target,
        diff: <int>[2],
        patchedHash: hashOf('two'),
        rolloutPercent: 0,
      );
      final Map<String, Object?> answer = source.check(
        _ask('client-7'),
        downloadBase: base,
      );
      expect(answer['patch_available'], isTrue);
      expect((answer['patch']! as Map<String, Object?>)['number'], 1);
      expect(
        source.check(
          _ask('client-7', current: 1),
          downloadBase: base,
        )['patch_available'],
        isFalse,
      );
    });

    test('a rollout is set over HTTP only with the token', () async {
      source.publish(
        target,
        diff: <int>[1],
        patchedHash: hashOf('one'),
        rolloutPercent: 0,
      );
      final Map<String, Object?> body = <String, Object?>{
        'app_id': 'shop',
        'release_version': '1.0.0+1',
        'platform': 'ios',
        'number': 1,
        'percent': 100,
      };
      expect(
        (await source.respond(
          _request('POST', '/_dartvel/rollout', json: body),
          prefix: '/updates',
        ))!.status,
        HttpStatus.unauthorized,
      );
      expect(source.patches(target).single.rolloutPercent, 0);
      final Response done = (await source.respond(
        _request('POST', '/_dartvel/rollout', json: body, authorized: true),
        prefix: '/updates',
      ))!;
      expect(done.status, HttpStatus.ok, reason: await _text(done));
      expect(source.patches(target).single.rolloutPercent, 100);
    });
  });

  group('signed releases', () {
    final bool haveOpenssl =
        Process.runSync('openssl', <String>['version']).exitCode == 0;
    late String privatePem;
    late String otherPem;
    late String releaseKey;

    setUpAll(() {
      if (!haveOpenssl) return;
      final Directory keys = Directory.systemTemp.createTempSync('dv_keys_');
      Process.runSync('openssl', <String>[
        'genrsa', '-out', '${keys.path}/a.pem', '2048', //
      ]);
      Process.runSync('openssl', <String>[
        'genrsa', '-out', '${keys.path}/b.pem', '2048', //
      ]);
      privatePem = File('${keys.path}/a.pem').readAsStringSync();
      otherPem = File('${keys.path}/b.pem').readAsStringSync();
      releaseKey = DVPatchSigning.releasePublicKeyOf(privatePem);
      keys.deleteSync(recursive: true);
    });

    test('a signed release takes only patches signed by its key', () async {
      source.registerRelease(
        appId: 'shop',
        releaseVersion: '1.0.0+1',
        platform: 'ios',
        patchPublicKey: releaseKey,
      );
      final String hash = hashOf('patched');
      expect(
        () => source.publish(target, diff: <int>[1], patchedHash: hash),
        throwsFormatException,
        reason: 'the release refuses unsigned patches on every device',
      );
      expect(
        () => source.publish(
          target,
          diff: <int>[1],
          patchedHash: hash,
          hashSignature: DVPatchSigning.signHash(hash, otherPem),
        ),
        throwsFormatException,
      );
      expect(source.patches(target), isEmpty);

      final String signature = DVPatchSigning.signHash(hash, privatePem);
      source.publish(
        target,
        diff: <int>[1],
        patchedHash: hash,
        hashSignature: signature,
      );
      final Map<String, Object?> patch =
          source.check(_ask('c'), downloadBase: base)['patch']!
              as Map<String, Object?>;
      expect(patch['hash_signature'], signature);
    }, skip: haveOpenssl ? false : 'openssl is not installed');

    test('a release is registered over HTTP with the token, and a forged '
        'patch is refused over HTTP', () async {
      final Map<String, Object?> release = <String, Object?>{
        'app_id': 'shop',
        'release_version': '1.0.0+1',
        'platform': 'ios',
        'patch_public_key': releaseKey,
      };
      expect(
        (await source.respond(
          _request('POST', '/_dartvel/release', json: release),
          prefix: '/updates',
        ))!.status,
        HttpStatus.unauthorized,
      );
      final Response registered = (await source.respond(
        _request('POST', '/_dartvel/release', json: release, authorized: true),
        prefix: '/updates',
      ))!;
      expect(
        registered.status,
        HttpStatus.created,
        reason: await _text(registered),
      );
      expect(
        source
            .releaseRecord(
              appId: 'shop',
              releaseVersion: '1.0.0+1',
              platform: 'ios',
            )
            ?.patchPublicKey,
        releaseKey,
      );
      final String hash = hashOf('patched');
      final Response forged = (await source.respond(
        _request(
          'POST',
          '/_dartvel/publish?app_id=shop&release_version=1.0.0%2B1'
              '&platform=ios&arch=aarch64&hash=$hash'
              '&hash_signature=${Uri.encodeQueryComponent(DVPatchSigning.signHash(hash, otherPem))}',
          body: <int>[1, 2, 3],
          authorized: true,
        ),
        prefix: '/updates',
      ))!;
      expect(forged.status, HttpStatus.badRequest);
      expect(source.patches(target), isEmpty);
    }, skip: haveOpenssl ? false : 'openssl is not installed');
  });

  group('installs', () {
    Future<int> report(Map<String, Object?> event) async =>
        (await source.respond(
          _request('POST', '/api/v1/patches/events', json: event),
          prefix: '/updates',
        ))!.status;

    test('an install is counted once per device per patch, a failure not at '
        'all, and the hook sees each counted install', () async {
      expect(await report(_event('a', 1)), HttpStatus.noContent);
      expect(await report(_event('a', 1)), HttpStatus.noContent);
      expect(await report(_event('b', 1)), HttpStatus.noContent);
      expect(await report(_event('a', 2)), HttpStatus.noContent);
      expect(
        await report(_event('c', 1, type: '__patch_install_failure__')),
        HttpStatus.noContent,
      );
      expect(
        await report(_event('c', 1, type: '__patch_download__')),
        HttpStatus.noContent,
      );

      final DVPatchInstallUsage usage = source.installUsage('shop');
      expect(usage.total, 3);
      expect(usage.byPatch, <String, int>{
        '1.0.0+1/ios/1': 2,
        '1.0.0+1/ios/2': 1,
      });
      expect(hooked.map((DVShorebirdPatchInstall i) => i.clientId), <String>[
        'a',
        'b',
        'a',
      ]);
      expect(hooked.first.month, '2026-10');
    });

    test(
      'installs are counted in the month the server received them',
      () async {
        now = DateTime.utc(2026, 9, 30, 23, 59);
        await report(_event('a', 1));
        now = DateTime.utc(2026, 10, 1, 0, 1);
        await report(_event('b', 1));
        await report(_event('c', 1));
        expect(source.installUsage('shop', month: '2026-09').total, 1);
        expect(source.installUsage('shop', month: '2026-10').total, 2);
        expect(
          source.installUsage('shop').total,
          2,
          reason: 'the current month by default',
        );
        expect(source.installUsage('other').total, 0);
        source.recordEvent(<String, Object?>{
          'event': <String, Object?>{
            ...(_event('z', 1)['event']! as Map<String, Object?>),
            'app_id': 'other',
          },
        });
        expect(source.installTotal(), 3, reason: 'every app the source serves');
        expect(source.installTotal(month: '2026-09'), 1);
      },
    );

    test('a body that is not JSON is refused, and an event that names no '
        'valid release is not counted', () async {
      expect(
        (await source.respond(
          _request('POST', '/api/v1/patches/events', body: utf8.encode('{')),
          prefix: '/updates',
        ))!.status,
        HttpStatus.badRequest,
      );
      final Map<String, Object?> bad = _event('a', 1);
      (bad['event']! as Map<String, Object?>)['app_id'] = '../escape';
      expect(await report(bad), HttpStatus.noContent);
      final Map<String, Object?> partial = _event('b', 1);
      (partial['event']! as Map<String, Object?>).remove('client_id');
      await report(partial);
      expect(source.installUsage('shop').total, 0);
    });
  });

  test('a source that may not offer patches offers none and still withdraws '
      'rolled-back ones', () {
    source.publish(target, diff: <int>[1], patchedHash: hashOf('one'));
    source.publish(target, diff: <int>[2], patchedHash: hashOf('two'));
    source.rollBack(target, 2);
    offering = false;
    final Map<String, Object?> answer = source.check(
      _ask('a', current: 2),
      downloadBase: base,
    );
    expect(answer['patch_available'], isFalse);
    expect(answer['rolled_back_patch_numbers'], <int>[2]);
  });

  test('the installs ledger cannot be named as an app', () {
    expect(
      () => source.publish(
        const DVShorebirdPatchTarget(
          appId: '_dartvel',
          releaseVersion: '1.0.0+1',
          platform: 'ios',
          arch: 'aarch64',
        ),
        diff: <int>[1],
        patchedHash: hashOf('x'),
      ),
      throwsFormatException,
    );
  });
}
