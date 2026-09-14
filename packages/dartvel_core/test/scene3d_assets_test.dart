// Asset references: what is allowed to be fetched, and what counts as loaded.
//
// The failures here do not throw on their own. A model fetched from a host
// nobody allowed renders. A storage key naming another tenant's upload
// renders. Bytes that changed behind a key render. So every refusal is checked
// before any request is made, and every load says exactly how it ended.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'scene3d_fixtures.dart';

DVSceneAsset _stored(String key, List<int> bytes, {String? digest}) => DVSceneAsset(
      kind: DVSceneAssetKind.model,
      source: DVSceneAssetSource.stored,
      reference: key,
      sha256: digest ?? sha256Hex(bytes),
    );

void main() {
  final List<int> kart = glb(kartGltf());

  group('policy, before any request', () {
    const DVSceneAssetPolicy policy = DVSceneAssetPolicy(
      allowedHosts: <String>{'cdn.example.com'},
    );

    DVSceneAssetRefusal? check(DVSceneAsset asset, [String tenant = 'acme']) =>
        policy.check(asset, tenant: tenant);

    test("a stored key under the current tenant's prefix is allowed", () {
      expect(check(_stored('tenants/acme/models/kart.glb', kart)), isNull);
    });

    test("a stored key under another tenant's prefix is refused", () {
      final DVSceneAssetRefusal? refusal =
          check(_stored('tenants/globex/models/kart.glb', kart));
      expect(refusal?.reason, contains('tenant'));
    });

    test('a stored key outside every tenant prefix is refused unless shared', () {
      expect(check(_stored('models/kart.glb', kart)), isNotNull);
      const DVSceneAssetPolicy shared = DVSceneAssetPolicy(
          sharedStoragePrefixes: <String>{'library/'});
      expect(shared.check(_stored('library/kart.glb', kart), tenant: 'acme'), isNull);
    });

    test('a key that climbs out of its prefix is refused', () {
      expect(check(_stored('tenants/acme/../globex/kart.glb', kart)), isNotNull);
    });

    test('a stored or network asset without a digest is refused', () {
      expect(
        check(const DVSceneAsset(
            kind: DVSceneAssetKind.model,
            source: DVSceneAssetSource.stored,
            reference: 'tenants/acme/kart.glb')),
        isNotNull,
      );
    });

    test('an https URL on an allowed host is allowed; anything else is not', () {
      DVSceneAsset net(String url) => DVSceneAsset(
          kind: DVSceneAssetKind.model,
          source: DVSceneAssetSource.network,
          reference: url,
          sha256: sha256Hex(kart));
      expect(check(net('https://cdn.example.com/kart.glb')), isNull);
      expect(check(net('https://CDN.example.com/kart.glb')), isNull);
      expect(check(net('http://cdn.example.com/kart.glb')), isNotNull);
      expect(check(net('https://cdn.example.com.evil.test/kart.glb')), isNotNull);
      expect(check(net('https://user@cdn.example.com/kart.glb')), isNotNull);
      expect(check(net('not a url')), isNotNull);
    });

    test('a declared size over the ceiling is refused before it is fetched', () {
      const DVSceneAssetPolicy small = DVSceneAssetPolicy(maxBytes: 100);
      const DVSceneAsset asset = DVSceneAsset(
        kind: DVSceneAssetKind.model,
        source: DVSceneAssetSource.bundled,
        reference: 'assets/models/kart.glb',
        byteLength: 101,
      );
      expect(small.check(asset, tenant: 'acme')?.reason, contains('bytes'));
    });

    test('a bundled key with a scheme or a parent segment is refused', () {
      DVSceneAsset bundled(String key) => DVSceneAsset(
          kind: DVSceneAssetKind.model,
          source: DVSceneAssetSource.bundled,
          reference: key);
      expect(check(bundled('assets/models/kart.glb')), isNull);
      expect(check(bundled('../secrets.glb')), isNotNull);
      expect(check(bundled('https://cdn.example.com/kart.glb')), isNotNull);
    });
  });

  group('loading', () {
    late List<String> fetched;
    late Map<String, List<int>> store;

    DVSceneAssetLoader loader({
      DVSceneAssetPolicy policy = const DVSceneAssetPolicy(),
      String tenant = 'acme',
      DVSceneAssetDecode? decode,
    }) =>
        DVSceneAssetLoader(
          policy: policy,
          tenant: () => tenant,
          decode: decode,
          fetchers: <DVSceneAssetSource, DVSceneAssetFetch>{
            DVSceneAssetSource.stored: (DVSceneAsset asset) async {
              fetched.add(asset.reference);
              return store[asset.reference];
            },
          },
        );

    setUp(() {
      fetched = <String>[];
      store = <String, List<int>>{'tenants/acme/kart.glb': kart};
    });

    test('a verified model loads, with what the inspector found', () async {
      final DVSceneAssetState state =
          await loader().load('kart', _stored('tenants/acme/kart.glb', kart));
      expect(state.status, DVSceneAssetStatus.ready);
      expect(state.model!.triangles, 19);
      expect(state.bytes, kart);
    });

    test('a refused asset is never requested', () async {
      final DVSceneAssetState state = await loader(tenant: 'globex')
          .load('kart', _stored('tenants/acme/kart.glb', kart));
      expect(state.status, DVSceneAssetStatus.failed);
      expect(state.failure, DVSceneAssetFailure.refused);
      expect(fetched, isEmpty);
    });

    test('bytes that do not match the digest are not ready', () async {
      store['tenants/acme/kart.glb'] = <int>[...kart]..[40] ^= 0xFF;
      final DVSceneAssetState state =
          await loader().load('kart', _stored('tenants/acme/kart.glb', kart));
      expect(state.failure, DVSceneAssetFailure.digestMismatch);
      expect(state.bytes, isNull);
    });

    test('nothing behind the key is missing, not failed', () async {
      final DVSceneAssetState state =
          await loader().load('kart', _stored('tenants/acme/gone.glb', kart));
      expect(state.failure, DVSceneAssetFailure.missing);
    });

    test('a storage not-found exception is missing too', () async {
      final DVSceneAssetLoader l = DVSceneAssetLoader(
        tenant: () => 'acme',
        fetchers: <DVSceneAssetSource, DVSceneAssetFetch>{
          DVSceneAssetSource.stored: (DVSceneAsset a) async =>
              throw DVFileStorageException('memory', 'get', a.reference, statusCode: 404),
        },
      );
      expect((await l.load('k', _stored('tenants/acme/x.glb', kart))).failure,
          DVSceneAssetFailure.missing);
    });

    test('a model whose bytes are not glTF is corrupt, even with a good digest',
        () async {
      final List<int> junk = <int>[1, 2, 3, 4, 5, 6, 7, 8];
      store['tenants/acme/junk.glb'] = junk;
      final DVSceneAssetState state =
          await loader().load('junk', _stored('tenants/acme/junk.glb', junk));
      expect(state.failure, DVSceneAssetFailure.corrupt);
      expect(state.reason, contains('glTF'));
    });

    test('fetched bytes over the ceiling are refused as too large', () async {
      final DVSceneAssetState state =
          await loader(policy: const DVSceneAssetPolicy(maxBytes: 64))
              .load('kart', _stored('tenants/acme/kart.glb', kart));
      expect(state.failure, DVSceneAssetFailure.tooLarge);
    });

    test('a source with no fetcher fails and says which', () async {
      final DVSceneAssetState state = await loader().load(
          'k',
          const DVSceneAsset(
              kind: DVSceneAssetKind.model,
              source: DVSceneAssetSource.bundled,
              reference: 'assets/models/kart.glb'));
      expect(state.failure, DVSceneAssetFailure.failed);
      expect(state.reason, contains('bundled'));
    });

    test('concurrent loads of one key share one request', () async {
      final DVSceneAssetLoader l = loader();
      final DVSceneAsset asset = _stored('tenants/acme/kart.glb', kart);
      await Future.wait(<Future<DVSceneAssetState>>[
        l.load('kart', asset),
        l.load('kart', asset),
      ]);
      expect(fetched, hasLength(1));
    });

    test('states move pending, loading, ready and are observable', () async {
      final DVSceneAssetLoader l = loader();
      final List<DVSceneAssetStatus> seen = <DVSceneAssetStatus>[];
      final StreamSubscription<DVSceneAssetChange> sub =
          l.changes.listen((DVSceneAssetChange c) => seen.add(c.state.status));
      expect(l.stateOf('kart').status, DVSceneAssetStatus.pending);
      await l.load('kart', _stored('tenants/acme/kart.glb', kart));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, <DVSceneAssetStatus>[DVSceneAssetStatus.loading, DVSceneAssetStatus.ready]);
    });

    test('decoding can run on the worker pool', () async {
      final DVWorkers workers = DVWorkers();
      addTearDown(workers.close);
      final DVSceneAssetState state = await loader(
        decode: DVSceneAssetLoader.decodeOn(workers),
      ).load('kart', _stored('tenants/acme/kart.glb', kart));
      expect(state.status, DVSceneAssetStatus.ready, reason: state.reason);
      expect(state.model!.bounds, DVGltf.inspect(kart).bounds);
    });
  });
}
