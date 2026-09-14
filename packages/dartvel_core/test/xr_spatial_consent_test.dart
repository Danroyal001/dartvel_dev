// Consent to keep environment data, read from the application's own consent
// records.
//
// Every failure here is a quiet one. A token that re-localizes a place in
// somebody's home is still on disk after they said no. A grant given under
// last year's policy stands for this year's. A withdrawal stops the next write
// and leaves the last one where it was. An erasure reaches every table and
// never the device the place was mapped on.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVConsentCategory environment = DVConsentCategory('environment');

final DVConsentPolicy policyV1 = DVConsentPolicy(
  version: '2026-09-01',
  categories: const <DVConsentDeclaration>[
    DVConsentDeclaration(DVConsentCategory.essential, required: true),
    DVConsentDeclaration(environment),
  ],
);

final DVConsentPolicy policyV2 = DVConsentPolicy(
  version: '2026-10-01',
  categories: policyV1.categories,
);

final List<int> _signingKey = List<int>.generate(32, (int i) => i * 7 % 256);

const DVSpatialSpaceRequest _volume = DVSpatialSpaceRequest(
  kind: DVSpatialSpaceKind.volume,
  route: '/showroom',
  volume: DVVolumeOptions(size: DVVec3(1.2, 0.8, 0.8)),
);

Future<void> _settle() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Permissions implements DVCapturePermissions {
  @override
  Future<bool> request(String permission) async => true;
}

/// Writes that can be made to fail, as a database that went away does.
final class _BreakableDatabase implements DVDatabaseAdapter {
  _BreakableDatabase(this.inner);

  final DVDatabaseAdapter inner;
  bool broken = false;

  @override
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? params]) =>
      inner.query(sql, params);

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    if (broken) throw StateError('the database is gone');
    return inner.execute(sql, params);
  }
}

/// What Product Analytics' consent adapter does to consent records on
/// erasure: keeps them, under the pseudonym.
final class _PseudonymizeConsent implements DVPrivacyAdapter {
  _PseudonymizeConsent(this.consent);

  final DVConsent consent;

  @override
  String get name => 'analytics:consent';

  @override
  Future<void> erase(DVPrivacySubjectRef subject) async =>
      consent.pseudonymize('${subject.id}', subject.pseudonym);

  @override
  Future<Map<String, Object?>> export(DVPrivacySubjectRef subject) async =>
      const <String, Object?>{};
}

void main() {
  late _BreakableDatabase database;
  late DVMemorySpatialAnchorStore tokens;

  setUp(() {
    database = _BreakableDatabase(MemoryDVDatabaseAdapter());
    tokens = DVMemorySpatialAnchorStore();
  });

  Future<DVConsent> consentUnder(DVConsentPolicy policy, {String installId = 'install-1'}) async {
    final DVConsent consent = DVConsent(
      policy: policy,
      database: database,
      installId: installId,
      onDiagnostic: (String code, String message) {},
    );
    await consent.ensureSchema();
    await consent.load();
    return consent;
  }

  /// Presents a volume holding one world anchor, and has the device locate
  /// it -- the moment a consenting session persists it.
  Future<(DVXRRuntime, DVXRFakeDevice)> locate(
    DVSpatialConsent consent,
    DVSpatialAnchorStore store, {
    String anchor = 'lobby-sign',
  }) async {
    final DVXRFakeDevice device = DVXRFakeDevice();
    final DVXRRuntime xr = DVXRRuntime(
      device: device,
      capability: DVSpatialCapability.headset(),
      permissions: _Permissions(),
      lifecycle: DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready),
      consent: consent,
      anchorStore: store,
      diagnostics: (String code, String message, Map<String, Object?> context) {},
    );
    final DVSpatialSession session = (await xr.present(_volume)).session!;
    await session.attach(DVSceneGraph(DV3DSceneDocument(id: 'shop', nodes: <DVSceneNodeData>[
      DVSceneNodeData(
        id: 'n0',
        kind: DVSceneNodeKind.mesh,
        primitive: const DVScenePrimitive.box(DVVec3(0.1, 0.1, 0.1)),
        anchor: DVAnchor.world(id: anchor),
      ),
    ])));
    device.emit(DVXRAnchorChanged(device.anchors.single,
        position: const DVVec3(1, 1, 1), orientation: DVQuat.identity));
    await _settle();
    return (xr, device);
  }

  group('whether keeping an anchor is agreed to', () {
    test('nothing is, until the declared category is granted -- and then only keeping one', () async {
      final DVConsent consent = await consentUnder(policyV1);
      final DVConsentSpatialConsent spatial =
          DVConsentSpatialConsent(consent, category: environment, anchors: tokens);
      addTearDown(spatial.dispose);

      expect(spatial.granted(DVSpatialDataUse.persistAnchors), isFalse);

      await consent.record(<DVConsentCategory, bool>{environment: true});
      expect(spatial.granted(DVSpatialDataUse.persistAnchors), isTrue);
      expect(spatial.granted(DVSpatialDataUse.shareAnchors), isFalse,
          reason: 'sending a place to another device is not what anybody was asked about');

      final (DVXRRuntime xr, DVXRFakeDevice _) = await locate(spatial, spatial.anchors);
      expect(await tokens.read('lobby-sign'), isNotNull);
      await xr.dispose();
    });

    test('a grant recorded under an older policy version does not permit it', () async {
      final DVConsent before = await consentUnder(policyV1);
      await before.record(<DVConsentCategory, bool>{environment: true});

      final DVConsent now = await consentUnder(policyV2);
      final DVConsentSpatialConsent spatial =
          DVConsentSpatialConsent(now, category: environment, anchors: tokens);
      addTearDown(spatial.dispose);

      expect(spatial.granted(DVSpatialDataUse.persistAnchors), isFalse);
      final (DVXRRuntime xr, DVXRFakeDevice device) = await locate(spatial, spatial.anchors);
      expect(device.calls, isNot(contains('xr.anchor.persist')));
      expect(await tokens.ids(), isEmpty);
      await expectLater(spatial.anchors.write('lobby-sign', 'token-1'),
          throwsA(isA<DVSpatialAnchorNotStored>()));
      expect(await tokens.ids(), isEmpty);
      await xr.dispose();
    });

    test('the category has to be one somebody is asked about', () async {
      final DVConsent consent = await consentUnder(policyV1);
      expect(
        () => DVConsentSpatialConsent(consent,
            category: const DVConsentCategory('undeclared'), anchors: tokens),
        throwsArgumentError,
      );
      expect(
        () => DVConsentSpatialConsent(consent, category: DVConsentCategory.essential, anchors: tokens),
        throwsArgumentError,
        reason: 'a required category is granted without anybody being asked',
      );
      final DVConsent defaulted = DVConsent(
        policy: DVConsentPolicy(version: '1', categories: const <DVConsentDeclaration>[
          DVConsentDeclaration(environment, defaultGranted: true),
        ]),
        database: database,
        installId: 'install-1',
      );
      expect(
        () => DVConsentSpatialConsent(defaulted, category: environment, anchors: tokens),
        throwsArgumentError,
        reason: 'a category granted by default is granted without anybody being asked',
      );
    });
  });

  group('withdrawal', () {
    test('stops keeping anchors at once, and deletes every token already kept', () async {
      final DVConsent consent = await consentUnder(policyV1);
      await consent.record(<DVConsentCategory, bool>{environment: true});
      final DVConsentSpatialConsent spatial =
          DVConsentSpatialConsent(consent, category: environment, anchors: tokens);
      addTearDown(spatial.dispose);
      final (DVXRRuntime xr, DVXRFakeDevice _) = await locate(spatial, spatial.anchors);
      // A token from an earlier launch, for an anchor no open scene names.
      await spatial.anchors.write('kitchen-shelf', 'token-earlier');
      expect(await tokens.ids(), unorderedEquals(<String>['lobby-sign', 'kitchen-shelf']));

      final Future<bool> withdrawn = consent.record(<DVConsentCategory, bool>{environment: false});
      await withdrawn;
      expect(spatial.granted(DVSpatialDataUse.persistAnchors), isFalse);

      await spatial.idle;
      expect(await tokens.ids(), isEmpty);
      await expectLater(spatial.anchors.write('lobby-sign', 'token-late'),
          throwsA(isA<DVSpatialAnchorNotStored>()));
      expect(await tokens.ids(), isEmpty);
      await xr.dispose();
    });

    test('that could not be recorded still deletes them', () async {
      final DVConsent consent = await consentUnder(policyV1);
      await consent.record(<DVConsentCategory, bool>{environment: true});
      final DVConsentSpatialConsent spatial =
          DVConsentSpatialConsent(consent, category: environment, anchors: tokens);
      addTearDown(spatial.dispose);
      await spatial.anchors.write('lobby-sign', 'token-1');

      database.broken = true;
      expect(await consent.record(<DVConsentCategory, bool>{environment: false}), isFalse);
      await spatial.idle;

      expect(spatial.granted(DVSpatialDataUse.persistAnchors), isFalse);
      expect(await tokens.ids(), isEmpty);
    });

    test('enforce, after loading, deletes tokens kept under an older version and keeps current ones',
        () async {
      final DVConsent before = await consentUnder(policyV1);
      await before.record(<DVConsentCategory, bool>{environment: true});
      await tokens.write('lobby-sign', 'token-1');

      final DVConsent now = await consentUnder(policyV2);
      final DVConsentSpatialConsent spatial =
          DVConsentSpatialConsent(now, category: environment, anchors: tokens);
      addTearDown(spatial.dispose);
      expect(await spatial.enforce(), 1);
      expect(await tokens.ids(), isEmpty);

      await now.record(<DVConsentCategory, bool>{environment: true});
      await spatial.anchors.write('lobby-sign', 'token-2');
      expect(await spatial.enforce(), 0);
      expect(await tokens.read('lobby-sign'), 'token-2');
    });
  });

  group('Data Compliance', () {
    Future<(DVConsent, DVConsentSpatialConsent, DVPrivacy)> setUpErasure({
      List<DVPrivacyAdapter> Function(DVConsent consent, DVConsentSpatialConsent spatial)? adapters,
    }) async {
      final DVConsent consent = await consentUnder(policyV1);
      await consent.record(<DVConsentCategory, bool>{environment: true}, userId: 'user-7');
      final DVConsentSpatialConsent spatial =
          DVConsentSpatialConsent(consent, category: environment, anchors: tokens);
      addTearDown(spatial.dispose);
      await spatial.anchors.write('lobby-sign', 'token-lobby');
      await spatial.anchors.write('kitchen-shelf', 'token-kitchen');
      final DVPrivacy privacy = DVPrivacy(
        models: const <DVPrivacyModel>[],
        database: database,
        signingKey: _signingKey,
        adapters: adapters?.call(consent, spatial) ??
            <DVPrivacyAdapter>[spatial.privacyAdapter()],
      );
      await privacy.ensureSchema();
      return (consent, spatial, privacy);
    }

    test('erasing the install deletes its anchor tokens, and the erasure is complete', () async {
      final (_, _, DVPrivacy privacy) = await setUpErasure();

      final DVErasureResult result =
          await privacy.erase(subject: 'install-1', reason: 'erasure request');

      expect(result.complete, isTrue);
      expect(await tokens.ids(), isEmpty);
    });

    test('a user consent records name on this install is tied to them -- whichever adapter runs first',
        () async {
      final (_, _, DVPrivacy privacy) = await setUpErasure(
        adapters: (DVConsent consent, DVConsentSpatialConsent spatial) => <DVPrivacyAdapter>[
          _PseudonymizeConsent(consent),
          spatial.privacyAdapter(),
        ],
      );

      final DVErasureResult result = await privacy.erase(subject: 'user-7', reason: 'erasure request');

      expect(result.complete, isTrue);
      expect(await tokens.ids(), isEmpty);
    });

    test('somebody this install never recorded is not tied to its tokens', () async {
      final (_, _, DVPrivacy privacy) = await setUpErasure();

      await privacy.erase(subject: 'user-9', reason: 'erasure request');

      expect(await tokens.ids(), hasLength(2));
    });

    test('export names the anchors kept and never hands out a token', () async {
      final (_, _, DVPrivacy privacy) = await setUpErasure();

      final DVExportArchive archive = await privacy.export(subject: 'user-7');

      expect(archive.adapters['xr:anchors'], <String, Object?>{
        'anchors': <String>['kitchen-shelf', 'lobby-sign'],
      });
      expect(archive.toJson(), isNot(contains('token-')));
    });
  });
}
