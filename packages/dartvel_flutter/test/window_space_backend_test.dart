// The extension point behind volumes and immersive spaces on DV.Window.
//
// Without a backend a volume or immersive request is a page and says why; with
// one registered, the backend decides what is presented in space, and the
// window carries its session and ends with it.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session implements DVWindowSpaceSession {
  final StreamController<void> _ended = StreamController<void>.broadcast();
  bool closed = false;

  @override
  Stream<void> get ended => _ended.stream;

  void endFromSystem() => _ended.add(null);

  @override
  Future<void> close() async {
    closed = true;
    await _ended.close();
  }
}

class _Backend implements DVWindowSpaceBackend {
  _Backend({this.capability, this.panels = false, this.refusal});

  @override
  final Object? capability;
  @override
  final bool panels;
  final DVWindowDegradation? refusal;
  final List<DVWindowSpaceRequest> requests = <DVWindowSpaceRequest>[];
  final List<_Session> sessions = <_Session>[];
  int resets = 0;

  @override
  Future<DVWindowSpacePresentation> present(DVWindowSpaceRequest request) async {
    requests.add(request);
    if (refusal != null) {
      return DVWindowSpacePresentation.refused(refusal!, codes: const <String>['DV-WINDOW-004', 'DV-WINDOW-014']);
    }
    final _Session session = _Session();
    sessions.add(session);
    return DVWindowSpacePresentation.presented(session);
  }

  @override
  void reset() => resets++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DVWindowManager.reset();
    DVWindowManager.unregisterSpaceBackend();
  });

  group('with no backend registered', () {
    test('a volume is a page and says DV-WINDOW-014, not DV-WINDOW-001', () async {
      final DVWindow window = await DV.Platform.window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );
      expect(window.presentation, DVWindowPresentation.page);
      expect(window.degradation, DVWindowDegradation.capabilityUnsupported);
      expect(window.codes, <String>['DV-WINDOW-014']);
      expect(window.spatial, isNull);
      expect(DV.Platform.window.capability.spatial, isNull);
    });

    test('an immersive space is a page and says DV-WINDOW-015', () async {
      final DVWindow window = await DV.Platform.window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(kind: DVWindowKind.immersive),
      );
      expect(window.presentation, DVWindowPresentation.page);
      expect(window.codes, <String>['DV-WINDOW-015']);
    });
  });

  group('with a backend', () {
    test('its capability is what DV.Window reports', () {
      const Object capability = 'headset';
      DVWindowManager.registerSpaceBackend(_Backend(capability: capability));
      expect(DV.Platform.window.capability.spatial, capability);
    });

    test('panels let a tab tear out, and displays are not offered in space', () {
      DVWindowManager.registerSpaceBackend(_Backend(capability: 'headset', panels: true));
      final DVWindowingCapability capability = DV.Platform.window.capability;
      expect(capability.tearOut, isTrue);
      expect(capability.displays, isFalse);
    });

    test('a backend that reports no capability changes nothing', () {
      DVWindowManager.registerSpaceBackend(_Backend());
      expect(DV.Platform.window.capability.spatial, isNull);
      expect(DV.Platform.window.capability.tearOut, isFalse);
    });

    test('the request carries the kind, the route and the options', () async {
      final _Backend backend = _Backend(capability: 'headset');
      DVWindowManager.registerSpaceBackend(backend);
      await DV.Platform.window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume, space: 'volume-hint'),
      );
      expect(backend.requests.single.kind, DVWindowKind.volume);
      expect(backend.requests.single.route, '/showroom');
      expect(backend.requests.single.options, 'volume-hint');
    });

    test('a presented space is a window in that presentation, owned by main', () async {
      final _Backend backend = _Backend(capability: 'headset');
      DVWindowManager.registerSpaceBackend(backend);
      final DVWindow window = await DV.Platform.window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );
      expect(window.presentation, DVWindowPresentation.volume);
      expect(window.degradation, DVWindowDegradation.none);
      expect(window.spatial, same(backend.sessions.single));
    });

    test('closing the window closes its space', () async {
      final _Backend backend = _Backend(capability: 'headset');
      DVWindowManager.registerSpaceBackend(backend);
      final DVWindow window = await DV.Platform.window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(kind: DVWindowKind.immersive),
      );
      expect(window.presentation, DVWindowPresentation.immersive);
      await window.close();
      expect(backend.sessions.single.closed, isTrue);
    });

    test('the system ending the space closes the window', () async {
      final _Backend backend = _Backend(capability: 'headset');
      DVWindowManager.registerSpaceBackend(backend);
      await DV.Platform.window.open(
        const DVRouteTarget('/tour'),
        options: const DVWindowOptions(kind: DVWindowKind.immersive),
      );
      expect(DV.Platform.window.all.value, hasLength(1));
      backend.sessions.single.endFromSystem();
      await Future<void>.delayed(Duration.zero);
      expect(DV.Platform.window.all.value, isEmpty);
    });

    test('a refusal is a page with the degradation and codes the backend gave', () async {
      DVWindowManager.registerSpaceBackend(
        _Backend(capability: 'headset', refusal: DVWindowDegradation.platformRefused),
      );
      final DVWindow window = await DV.Platform.window.open(
        const DVRouteTarget('/showroom'),
        options: const DVWindowOptions(kind: DVWindowKind.volume),
      );
      expect(window.presentation, DVWindowPresentation.page);
      expect(window.degradation, DVWindowDegradation.platformRefused);
      expect(window.codes, <String>['DV-WINDOW-004', 'DV-WINDOW-014']);
    });

    test('resetting the window manager resets the backend but keeps it registered', () {
      final _Backend backend = _Backend(capability: 'headset');
      DVWindowManager.registerSpaceBackend(backend);
      DVWindowManager.reset();
      expect(backend.resets, 1);
      expect(DVWindowManager.spaceBackend, same(backend));
    });
  });
}
