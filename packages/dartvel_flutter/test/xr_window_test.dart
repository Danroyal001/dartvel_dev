// Volumes and immersive spaces as window kinds on DV.Platform.Window.
//
// Application code never branches on whether it is in a headset: open() is
// called the same way everywhere and presents the route the best way the
// target can. The silent failures are a volume or immersive request that
// quietly became a page with nothing on the window saying so, a code on the
// window that names the wrong cause (DV-WINDOW-001 is "no multi-window", not
// "no immersive space"), and a space that outlives the window that owns it --
// a camera still on after the page that asked for it is gone.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await DVXR.reset();
    DVWindowManager.reset();
  });

  group('where XR is absent', () {
    test('a volume is a page, and says DV-WINDOW-014 -- not DV-WINDOW-001', () async {
      DV.Test.fakeXR(null);

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/showroom'),
        options: DVWindowOptions(
          kind: DVWindowKind.volume,
          volume: DVVolumeOptions.checked(const DVVec3(1.2, 0.8, 0.8)),
        ),
      );

      expect(window.presentation, DVWindowPresentation.page);
      expect(window.degradation, isNot(DVWindowDegradation.none));
      expect(window.codes, <String>['DV-WINDOW-014']);
      expect(window.spatial, isNull);
      expect(DV.Platform.Window.capability.spatial, isNull);
    });

    test('an immersive space is a page, and says DV-WINDOW-015', () async {
      DV.Test.fakeXR(null);

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(
          kind: DVWindowKind.immersive,
          immersion: DVImmersion.passthrough,
        ),
      );

      expect(window.presentation, DVWindowPresentation.page);
      expect(window.codes, <String>['DV-WINDOW-015']);
    });

    test('glasses are not headsets: a volume is still a page', () async {
      DV.Test.fakeXR(DVSpatialCapability.glasses());

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );

      expect(window.presentation, DVWindowPresentation.page);
      expect(window.codes, <String>['DV-WINDOW-014']);
      expect(DV.Platform.Window.capability.spatial, isNotNull,
          reason: 'glasses report a capability; it just has no volumes');
    });

    test('windowing disabled in configuration names that cause first', () async {
      DV.Test.fakeXR(DVSpatialCapability.headset());
      DVWindowManager.useWindowingDeclaration(const DVWindowingDeclaration(enabled: false));
      addTearDown(DVWindowManager.resetWindowingDeclaration);

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );

      expect(window.presentation, DVWindowPresentation.page);
      expect(window.degradation, DVWindowDegradation.disabledByConfig);
      expect(window.codes, <String>['DV-WINDOW-005', 'DV-WINDOW-014']);
    });
  });

  group('on a headset', () {
    test('a volume is presented in space, with no degradation and no code', () async {
      final DVXRFakeDevice device = DV.Test.fakeXR(DVSpatialCapability.headset())!;

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );

      expect(window.presentation, DVWindowPresentation.volume);
      expect(window.degradation, DVWindowDegradation.none);
      expect(window.codes, isEmpty);
      expect(window.spatial!.state.value, DVSpatialSessionState.running);
      expect(device.openSpaces, 1);
    });

    test('closing the window ends its space', () async {
      final DVXRFakeDevice device = DV.Test.fakeXR(DVSpatialCapability.headset())!;
      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );

      final List<DVWindowLifecycle> seen = <DVWindowLifecycle>[];
      window.lifecycle.addListener(() => seen.add(window.lifecycle.value));

      await window.close();
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(seen, <DVWindowLifecycle>[DVWindowLifecycle.closing, DVWindowLifecycle.closed],
          reason: 'the ended session must not close the window a second time');
      expect(window.spatial!.state.value, DVSpatialSessionState.ended);
      expect(device.openSpaces, 0);
      expect(device.openSessions, 0);
      expect(DVXR.runtime.sessions, isEmpty);
    });

    test('an immersive space belongs to the window that opened it, and closes with it', () async {
      final DVXRFakeDevice device = DV.Test.fakeXR(DVSpatialCapability.headset())!;
      final DVWindow main = await DV.Platform.Window.open(const DVRouteTarget('/home'));
      final DVWindow tour = await DV.Platform.Window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(
          kind: DVWindowKind.immersive,
          immersion: DVImmersion.passthrough,
        ),
      );
      expect(tour.presentation, DVWindowPresentation.immersive);
      expect(tour.owner, same(main));
      expect(device.cameraOn, isTrue);

      await main.close();

      expect(tour.lifecycle.value, DVWindowLifecycle.closed);
      expect(device.cameraOn, isFalse);
      expect(device.openSessions, 0);
    });

    test('a second immersive space is a page with DV-WINDOW-015; the first is untouched', () async {
      final DVXRFakeDevice device = DV.Test.fakeXR(DVSpatialCapability.headset())!;
      final DVWindow first = await DV.Platform.Window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(kind: DVWindowKind.immersive),
      );
      final DVWindow second = await DV.Platform.Window.open(
        const DVRouteTarget('/other'),
        options: const DVWindowOptions(kind: DVWindowKind.immersive),
      );

      expect(first.presentation, DVWindowPresentation.immersive);
      expect(second.presentation, DVWindowPresentation.page);
      expect(second.codes, <String>['DV-WINDOW-015']);
      expect(device.openSpaces, 1);
    });

    test('the system ending the space closes the window', () async {
      final DVXRFakeDevice device = DV.Test.fakeXR(DVSpatialCapability.headset())!;
      final DVWindow tour = await DV.Platform.Window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(kind: DVWindowKind.immersive),
      );

      final List<DVWindowLifecycle> seen = <DVWindowLifecycle>[];
      tour.lifecycle.addListener(() => seen.add(tour.lifecycle.value));

      device.emit(const DVXRSpaceEnded());
      for (int i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(tour.lifecycle.value, DVWindowLifecycle.closed);
      expect(DV.Platform.Window.all.value, isNot(contains(tour)));
      // Closing the window ends the space, which would close the window again:
      // it closes once.
      expect(seen, <DVWindowLifecycle>[DVWindowLifecycle.closing, DVWindowLifecycle.closed]);
    });

    test('a refused camera is a full space with DV-XR-001 on the session, not a silent swap', () async {
      DV.Test.fakeXR(DVSpatialCapability.headset(), grantCamera: false);
      final DVWindow tour = await DV.Platform.Window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(
          kind: DVWindowKind.immersive,
          immersion: DVImmersion.passthrough,
        ),
      );

      expect(tour.presentation, DVWindowPresentation.immersive);
      expect(tour.spatial!.immersion.value, DVImmersion.full);
      expect(tour.spatial!.codes, contains('DV-XR-001'));
    });

    test('a display hint in space is ignored with DV-WINDOW-013, never matched to the headset', () async {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      DV.Test.fakeXR(DVSpatialCapability.headset());
      // A display the hint would match anywhere else: primary, and connected.
      // Without it the miss below would happen whether or not space is checked.
      DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
            <String, Object?>{
              'id': 'panel',
              'width': 1920.0,
              'height': 1080.0,
              'devicePixelRatio': 1.0,
              'isPrimary': true,
            },
          ]);
      addTearDown(() => DVNativeBridge.unregister('window.displays'));
      DVNativeBridge.register('window.open', (Object? arguments) => 'w1');
      addTearDown(() => DVNativeBridge.unregister('window.open'));

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/orders'),
        options: const DVWindowOptions(display: DVDisplayHint.primary),
      );

      expect(window.degradation, DVWindowDegradation.displayHintUnmatched);
      expect(window.codes, contains('DV-WINDOW-013'));
    });

    test('displays do not exist in space, and tearing a tab out still works', () async {
      DV.Test.fakeWindowing(const DVWindowingCapability(multiWindow: true, displayKiosk: true));
      DV.Test.fakeXR(DVSpatialCapability.headset());

      final DVWindowingCapability cap = DV.Platform.Window.capability;
      expect(cap.spatial, isNotNull);
      expect(cap.displays, isFalse);
      expect(cap.displayKiosk, isFalse);
      expect(cap.tearOut, isTrue);
    });
  });

  group('where the binding is missing', () {
    test('a reported capability with no bindings behind it is DV-XR-006, and still presents', () async {
      DVXR.install(capability: DVSpatialCapability.headset(), device: const DVXRBindingDevice());

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );

      expect(window.presentation, DVWindowPresentation.page);
      expect(window.degradation, DVWindowDegradation.bindingRefused);
      expect(window.codes, <String>['DV-XR-006', 'DV-WINDOW-014']);
    });

    test('refresh with no capability binding is not a headset', () async {
      expect(await DVXR.refresh(), isNull);
      expect(DV.Platform.Window.capability.spatial, isNull);
    });

    test('refresh reads what the binding reports, and a garbled report is DV-XR-006', () async {
      DVNativeBridge.register('xr.capability.query',
          (Object? _) => DVSpatialCapability.glasses().toJson());
      addTearDown(() => DVNativeBridge.unregister('xr.capability.query'));
      expect(await DVXR.refresh(), DVSpatialCapability.glasses());

      DVNativeBridge.register('xr.capability.query', (Object? _) => 'headset');
      expect(await DVXR.refresh(), isNull);
      expect(DVXR.lastBindingFailure, 'xr.capability.query');
    });
  });

  group('anchors in the shared store', () {
    // A token that re-localizes a place in somebody's home. Distinctive, so a
    // copy of it anywhere in the stored bytes is found.
    const String token = 'token-kitchen-4f2a9c';

    late DVMemoryAppKeyStore keys;
    late _RawBackend backend;

    setUp(() {
      keys = DVMemoryAppKeyStore();
      backend = _RawBackend();
    });

    DVWindowSharedStore storeWith({DVAppKeyStoreSource? appKeys, bool keyed = true}) =>
        DVWindowSharedStore(
          backend: backend,
          debounce: Duration.zero,
          appKeys: appKeys ?? (keyed ? () async => keys : null),
        );

    test('tokens live under the reserved xr. namespace an application cannot write', () async {
      final DVWindowSharedStore shared = storeWith();
      final DVSpatialAnchorStore store = DVSharedStoreAnchorStore(shared);
      await store.write('lobby-sign', 'token-1');

      expect(await store.read('lobby-sign'), 'token-1');
      expect(await shared.keys(), contains('xr.anchors.lobby-sign'));
      expect(await store.ids(), <String>['lobby-sign']);
      expect(() => shared.set('xr.anchors.lobby-sign', const DVJsonString('forged')),
          throwsA(isA<DVSharedStoreKeyError>()));

      await store.remove('lobby-sign');
      expect(await store.read('lobby-sign'), isNull);
    });

    test('a store given no cipher still never writes a token in plaintext', () async {
      await DVSharedStoreAnchorStore(storeWith()).write('lobby-sign', token);

      final String? raw = backend.values['xr.anchors.lobby-sign'];
      expect(raw, isNotNull);
      expect(raw, isNot(contains(token)));

      // Encrypted under the application key, not merely encoded: the same
      // bytes read back under that key, and under no other.
      expect(await DVSharedStoreAnchorStore(storeWith()).read('lobby-sign'), token);
      final DVMemoryAppKeyStore otherKey = DVMemoryAppKeyStore();
      expect(
        await DVSharedStoreAnchorStore(storeWith(appKeys: () async => otherKey)).read('lobby-sign'),
        isNull,
      );
    });

    test('a token large enough to spill is not written in plaintext either', () async {
      final DVMemoryFileStorageAdapter files = DVMemoryFileStorageAdapter();
      final DVWindowSharedStore shared = DVWindowSharedStore(
        backend: backend,
        debounce: Duration.zero,
        spillStorage: files,
        spillThresholdBytes: 1,
        appKeys: () async => keys,
      );
      await DVSharedStoreAnchorStore(shared).write('lobby-sign', token);

      final List<int> object = await files.get('dartvel/window-shared/xr.anchors.lobby-sign');
      expect(String.fromCharCodes(object), isNot(contains(token)));
      expect(backend.values['xr.anchors.lobby-sign'], isNot(contains(token)));
      shared.evictCache();
      expect(await DVSharedStoreAnchorStore(shared).read('lobby-sign'), token);
    });

    test('with no application key on the platform it refuses, and keeps nothing', () async {
      final List<(String, DVAppKeyStoreSource)> noKey = <(String, DVAppKeyStoreSource)>[
        ('no key store', () async => null),
        // What the web key store answers off the web: nothing to read, and a
        // write that throws.
        ('a key store that cannot hold a key', () async => const DVWebCryptoAppKeyStore(app: 'shop')),
        ('a key store that throws', () async => throw StateError('keyring locked')),
      ];
      for (final (String why, DVAppKeyStoreSource source) in noKey) {
        backend = _RawBackend();
        final DVWindowSharedStore shared = storeWith(appKeys: source);
        final DVSharedStoreAnchorStore store = DVSharedStoreAnchorStore(shared);

        await expectLater(store.write('lobby-sign', token),
            throwsA(isA<DVSpatialAnchorNotStored>()), reason: why);
        await expectLater(shared.setReserved('xr.anchors.lobby-sign', const DVJsonString(token)),
            throwsA(isA<DVSharedStoreSealUnavailable>()), reason: why);
        expect(backend.values, isEmpty, reason: why);
        expect(await store.read('lobby-sign'), isNull,
            reason: '$why: a token held in memory would read back as if it had been kept');
      }
    });

    test('a store nobody configured refuses rather than writing plaintext', () async {
      await expectLater(DVSharedStoreAnchorStore(storeWith(keyed: false)).write('lobby-sign', token),
          throwsA(isA<DVSpatialAnchorNotStored>()));
      expect(backend.values, isEmpty);
    });

    test('the application key configured once reaches a store made without one', () async {
      DVWindowSharedStore.defaultAppKeys = () async => keys;
      addTearDown(() => DVWindowSharedStore.defaultAppKeys = DVWindowSharedStore.noAppKeys);

      await DVSharedStoreAnchorStore(storeWith(keyed: false)).write('lobby-sign', token);

      expect(backend.values['xr.anchors.lobby-sign'], isNot(contains(token)));
      expect(await DVSharedStoreAnchorStore(storeWith(keyed: false)).read('lobby-sign'), token);
    });

    test('removing a token needs no key, so a withdrawal can always delete it', () async {
      await DVSharedStoreAnchorStore(storeWith()).write('lobby-sign', token);

      final DVSharedStoreAnchorStore keyless =
          DVSharedStoreAnchorStore(storeWith(appKeys: () async => null));
      await keyless.remove('lobby-sign');

      expect(backend.values, isEmpty);
      expect(await keyless.ids(), isEmpty);
    });

    test('a token an earlier version left in plaintext is not read as a token', () async {
      backend.values['xr.anchors.lobby-sign'] = '"$token"';

      expect(await DVSharedStoreAnchorStore(storeWith()).read('lobby-sign'), isNull);
    });

    test('view state is untouched: it is still written with the store cipher alone', () async {
      await storeWith().set('shop.activeTab', const DVJsonString('orders'));

      expect(backend.values['shop.activeTab'], '"orders"');
    });
  });
}

/// The bytes a backend was handed, exactly.
class _RawBackend extends DVSharedStoreBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<List<String>> keys() async => values.keys.toList(growable: false);
}
