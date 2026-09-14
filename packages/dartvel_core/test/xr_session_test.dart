// A presentation in space, against the headless device.
//
// Every assertion here is about a failure nobody sees on a desk: the camera
// still open after the headset is taken off, tracking still running behind
// the home screen, a passthrough request that became a full VR space without
// anybody being told, an anchor written to storage nobody agreed to, a head
// pose in a log line, a session still holding the device after its window
// went away.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final class _Permissions implements DVCapturePermissions {
  _Permissions();
  bool granted = true;
  final List<String> asked = <String>[];

  @override
  Future<bool> request(String permission) async {
    asked.add(permission);
    return granted;
  }
}

final class _Consent implements DVSpatialConsent {
  _Consent();
  Set<DVSpatialDataUse> allowed = const <DVSpatialDataUse>{};

  @override
  bool granted(DVSpatialDataUse use) => allowed.contains(use);
}

final class _Report {
  _Report(this.code, this.message, this.context);
  final String code;
  final String message;
  final Map<String, Object?> context;

  @override
  String toString() => '$code $message $context';
}

Future<void> _settle() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const DVSpatialSpaceRequest _passthrough = DVSpatialSpaceRequest(
  kind: DVSpatialSpaceKind.immersive,
  route: '/tour',
  immersion: DVImmersion.passthrough,
);

const DVSpatialSpaceRequest _volume = DVSpatialSpaceRequest(
  kind: DVSpatialSpaceKind.volume,
  route: '/showroom',
  volume: DVVolumeOptions(size: DVVec3(1.2, 0.8, 0.8)),
);

void main() {
  late DVXRFakeDevice device;
  late DVMutableLifecycleSignal<DVAppLifecycle> lifecycle;
  late _Permissions permissions;
  late _Consent consent;
  late DVMemorySpatialAnchorStore store;
  late List<_Report> reports;

  DVXRRuntime runtime({
    DVSpatialCapability? capability,
    DVXRDevice? withDevice,
    bool noDevice = false,
  }) =>
      DVXRRuntime(
        device: noDevice ? null : (withDevice ?? device),
        capability: capability ?? DVSpatialCapability.headset(),
        permissions: permissions,
        lifecycle: lifecycle,
        consent: consent,
        anchorStore: store,
        diagnostics: (String code, String message, Map<String, Object?> context) =>
            reports.add(_Report(code, message, context)),
      );

  setUp(() {
    device = DVXRFakeDevice();
    lifecycle = DVMutableLifecycleSignal<DVAppLifecycle>(DVAppLifecycle.ready);
    permissions = _Permissions();
    consent = _Consent();
    store = DVMemorySpatialAnchorStore();
    reports = <_Report>[];
  });

  group('presenting', () {
    test('a volume on a headset is presented in space and running', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialPresentation p = await xr.present(_volume);

      expect(p.inSpace, isTrue);
      expect(p.codes, isEmpty);
      final DVSpatialSession session = p.session!;
      expect(session.state.value, DVSpatialSessionState.running);
      expect(session.tracking.value, isTrue);
      expect(session.immersion.value, isNull, reason: 'a volume has no immersion');
      expect(device.openSessions, 1);
      expect(device.openSpaces, 1);
      expect(device.cameraOn, isFalse, reason: 'a volume never opens the camera');
      expect(permissions.asked, isEmpty);
      await xr.dispose();
    });

    test('no spatial capability: not in space, and the window code says which', () async {
      for (final (DVSpatialSpaceRequest request, String code) in <(DVSpatialSpaceRequest, String)>[
        (_volume, 'DV-WINDOW-014'),
        (_passthrough, 'DV-WINDOW-015'),
      ]) {
        final DVXRRuntime xr = DVXRRuntime(
          device: null,
          capability: null,
          permissions: permissions,
          lifecycle: lifecycle,
          diagnostics: (String c, String m, Map<String, Object?> x) => reports.add(_Report(c, m, x)),
        );
        final DVSpatialPresentation p = await xr.present(request);
        expect(p.inSpace, isFalse);
        expect(p.refusal, DVSpatialRefusal.noCapability);
        expect(p.codes, <String>[code]);
      }
      expect(device.calls, isEmpty);
    });

    test('glasses cannot present a volume', () async {
      final DVSpatialPresentation p =
          await runtime(capability: DVSpatialCapability.glasses()).present(_volume);
      expect(p.refusal, DVSpatialRefusal.noCapability);
      expect(p.codes, <String>['DV-WINDOW-014']);
      expect(device.calls, isEmpty);
    });

    test('a capability with no device behind it is the binding defect, DV-XR-006', () async {
      final DVSpatialPresentation p = await runtime(noDevice: true).present(_volume);
      expect(p.inSpace, isFalse);
      expect(p.refusal, DVSpatialRefusal.bindingMissing);
      expect(p.codes, <String>['DV-XR-006', 'DV-WINDOW-014']);
      expect(reports.map((_Report r) => r.code), contains('DV-XR-006'));
    });

    test('a binding that throws is DV-XR-006 and leaves nothing open', () async {
      device = DVXRFakeDevice(failing: <String>{'xr.space.open'});
      final DVSpatialPresentation p = await runtime().present(_volume);
      expect(p.refusal, DVSpatialRefusal.bindingFailed);
      expect(p.codes, <String>['DV-XR-006', 'DV-WINDOW-014']);
      expect(device.openSessions, 0, reason: 'the session opened before the space failed is closed');
    });

    test('a platform that declines is DV-WINDOW-004, not a defect', () async {
      device = DVXRFakeDevice(refusing: <String>{'xr.space.open'});
      final DVSpatialPresentation p = await runtime().present(_passthrough);
      expect(p.refusal, DVSpatialRefusal.platformRefused);
      expect(p.codes, <String>['DV-WINDOW-004', 'DV-WINDOW-015']);
      expect(device.openSessions, 0);
      expect(device.cameraOn, isFalse);
    });

    test('immersive spaces are exclusive: the second is refused and told', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialPresentation first = await xr.present(_passthrough);
      final DVSpatialPresentation second = await xr.present(
          const DVSpatialSpaceRequest(kind: DVSpatialSpaceKind.immersive, route: '/other'));
      expect(first.inSpace, isTrue);
      expect(second.inSpace, isFalse);
      expect(second.refusal, DVSpatialRefusal.exclusive);
      expect(second.codes, <String>['DV-WINDOW-015']);

      await first.session!.close();
      final DVSpatialPresentation third = await xr.present(
          const DVSpatialSpaceRequest(kind: DVSpatialSpaceKind.immersive, route: '/other'));
      expect(third.inSpace, isTrue, reason: 'once the first closed, a new one may open');
      await xr.dispose();
    });

    test('asked while backgrounded, nothing opens', () async {
      lifecycle.set(DVAppLifecycle.backgrounded);
      final DVSpatialPresentation p = await runtime().present(_volume);
      expect(p.refusal, DVSpatialRefusal.backgrounded);
      expect(device.calls, isEmpty);
    });
  });

  group('passthrough is the camera', () {
    test('it asks for the camera, and is on only once the device says so', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      expect(permissions.asked, <String>['camera']);
      expect(session.immersion.value, DVImmersion.passthrough);
      expect(session.passthrough.value, isTrue);
      expect(device.cameraOn, isTrue);
      await xr.dispose();
    });

    test('refused: a full space, lit by the studio, and DV-XR-001 -- never silently', () async {
      permissions.granted = false;
      final DVXRRuntime xr = runtime();
      final DVSpatialPresentation p = await xr.present(_passthrough);
      final DVSpatialSession session = p.session!;

      expect(p.inSpace, isTrue);
      expect(session.immersion.value, DVImmersion.full);
      expect(session.passthrough.value, isFalse);
      expect(session.lighting.value, DVSpatialLighting.studio);
      expect(session.codes, contains('DV-XR-001'));
      expect(device.cameraOn, isFalse);
      expect(device.calls, isNot(contains('xr.passthrough.set')));
      await xr.dispose();
    });

    test('a target without passthrough: the same, and the camera is not even asked for', () async {
      final DVXRRuntime xr = runtime(
        capability: const DVSpatialCapability(panels: true, volumes: true, immersive: true),
      );
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      expect(permissions.asked, isEmpty);
      expect(session.immersion.value, DVImmersion.full);
      expect(session.codes, contains('DV-XR-001'));
      await xr.dispose();
    });

    test('lit by the real environment only where a probe is available', () async {
      device = DVXRFakeDevice(probe: const DVSpatialLightProbe(intensity: 0.8));
      final DVXRRuntime xr = runtime();
      final DVSpatialSession lit = (await xr.present(_passthrough)).session!;
      expect(lit.lighting.value, DVSpatialLighting.realEnvironment);
      expect(lit.codes, isNot(contains('DV-XR-001')));
      await xr.dispose();

      device = DVXRFakeDevice();
      final DVXRRuntime unlit = runtime();
      final DVSpatialSession noProbe = (await unlit.present(_passthrough)).session!;
      expect(noProbe.lighting.value, DVSpatialLighting.studio);
      expect(noProbe.codes, contains('DV-XR-001'));
      await unlit.dispose();
    });

    test('revoked mid-session: the camera is off, immersion is full, and it says so', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      final List<DVImmersion?> seen = <DVImmersion?>[];
      session.immersion.listen(seen.add);

      device.emit(const DVXRPermissionRevoked('camera'));
      await _settle();

      expect(device.cameraOn, isFalse);
      expect(session.passthrough.value, isFalse);
      expect(session.immersion.value, DVImmersion.full);
      expect(seen, <DVImmersion?>[DVImmersion.full]);
      expect(session.codes, contains('DV-XR-001'));
      expect(session.state.value, DVSpatialSessionState.running);
      await xr.dispose();
    });
  });

  group('lifecycle', () {
    test('backgrounding stops the camera and tracking before anything else', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      expect(device.cameraOn, isTrue);

      lifecycle.set(DVAppLifecycle.backgrounded);
      await _settle();

      expect(session.state.value, DVSpatialSessionState.paused);
      expect(device.cameraOn, isFalse);
      expect(device.openSessions, 0, reason: 'tracking stops with the session');
      expect(device.openSpaces, 0);
      expect(session.passthrough.value, isFalse);
      expect(session.tracking.value, isFalse);
      await xr.dispose();
    });

    test('resuming asks for the camera again, because it can be revoked from settings', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      lifecycle.set(DVAppLifecycle.backgrounded);
      await _settle();

      permissions.granted = false;
      lifecycle.set(DVAppLifecycle.ready);
      await _settle();

      expect(session.state.value, DVSpatialSessionState.running);
      expect(permissions.asked, <String>['camera', 'camera']);
      expect(device.cameraOn, isFalse);
      expect(session.immersion.value, DVImmersion.full);
      expect(session.tracking.value, isTrue);
      expect(device.openSessions, 1);
      await xr.dispose();
    });

    test('closing releases everything once, and a second close is a no-op', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      await session.close();
      await session.close();

      expect(session.state.value, DVSpatialSessionState.ended);
      expect(device.cameraOn, isFalse);
      expect(device.openSessions, 0);
      expect(device.openSpaces, 0);
      expect(xr.sessions, isEmpty);

      lifecycle.set(DVAppLifecycle.backgrounded);
      lifecycle.set(DVAppLifecycle.ready);
      await _settle();
      expect(device.openSessions, 0, reason: 'a closed session never reopens on resume');
    });

    test('closed while backgrounded, it does not come back', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      lifecycle.set(DVAppLifecycle.backgrounded);
      await _settle();
      await session.close();
      lifecycle.set(DVAppLifecycle.ready);
      await _settle();
      expect(session.state.value, DVSpatialSessionState.ended);
      expect(device.openSessions, 0);
    });

    test('an event stream that breaks ends the session: nothing would hear a revocation', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      expect(device.cameraOn, isTrue);

      device.emitError(const DVXRBindingException('xr.input.observe', 'the pipe closed'));
      await _settle();

      expect(session.state.value, DVSpatialSessionState.ended);
      expect(device.cameraOn, isFalse);
      expect(device.openSessions, 0);
      expect(session.codes, contains('DV-XR-006'));
    });

    test('the system ending the space ends the session', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      device.emit(const DVXRSpaceEnded());
      await _settle();
      expect(session.state.value, DVSpatialSessionState.ended);
      expect(device.cameraOn, isFalse);
      expect(device.openSessions, 0);
      expect(xr.sessions, isEmpty);
    });

    test('disposing the runtime closes every session it opened', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession a = (await xr.present(_volume)).session!;
      final DVSpatialSession b = (await xr.present(_passthrough)).session!;
      await xr.dispose();
      expect(a.state.value, DVSpatialSessionState.ended);
      expect(b.state.value, DVSpatialSessionState.ended);
      expect(device.openSessions, 0);
      expect(device.cameraOn, isFalse);
    });
  });

  group('anchors', () {
    DV3DSceneDocument scene(List<DVAnchor> anchors) => DV3DSceneDocument(
          id: 'shop',
          nodes: <DVSceneNodeData>[
            for (int i = 0; i < anchors.length; i++)
              DVSceneNodeData(
                id: 'n$i',
                kind: DVSceneNodeKind.mesh,
                primitive: const DVScenePrimitive.box(DVVec3(0.1, 0.1, 0.1)),
                anchor: anchors[i],
              ),
          ],
        );

    test('a supported anchor is hidden until the device locates it, then placed in world space', () async {
      device = DVXRFakeDevice(
        convention: const DVSpatialConvention(handedness: DVSceneHandedness.left),
      );
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      final DVSceneGraph graph = DVSceneGraph(scene(<DVAnchor>[const DVAnchor.plane(DVPlane.vertical)]));
      await session.attach(graph);

      expect(graph.anchorPlacementOf('n0'), DVSceneAnchorPlacement.hidden);
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.searching);

      device.emit(DVXRAnchorChanged(device.anchors.single,
          position: const DVVec3(0, 1, 2), orientation: DVQuat.identity));
      await _settle();

      expect(graph.anchorPlacementOf('n0'), DVSceneAnchorPlacement.located);
      // Two metres forward in a left-handed device is -Z in the world.
      final DVVec3 p = graph.worldPosition('n0');
      expect(p.z, closeTo(-2, 1e-9));
      expect(p.y, closeTo(1, 1e-9));
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.tracking);

      device.emit(DVXRAnchorChanged(device.anchors.single));
      await _settle();
      expect(graph.anchorPlacementOf('n0'), DVSceneAnchorPlacement.hidden,
          reason: 'lost tracking hides it rather than leaving it where it was');
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.lost);
      await xr.dispose();
    });

    test('an unsupported anchor type is placed at the origin and reports DV-XR-002', () async {
      final DVXRRuntime xr = runtime(
        capability: const DVSpatialCapability(
            panels: true, volumes: true, anchors: <DVAnchorType>{DVAnchorType.plane}),
      );
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      final DVSceneGraph graph = DVSceneGraph(scene(<DVAnchor>[const DVAnchor.image('counterTag')]));
      await session.attach(graph);

      expect(graph.anchorPlacementOf('n0'), DVSceneAnchorPlacement.origin);
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.unsupported);
      expect(session.codes, contains('DV-XR-002'));
      expect(device.calls, isNot(contains('xr.anchor.create')));
      await xr.dispose();
    });

    test('a world anchor is not persisted without consent', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      await session.attach(DVSceneGraph(scene(<DVAnchor>[const DVAnchor.world(id: 'lobby-sign')])));
      // Located, which is the moment a consenting session would persist it:
      // without this the assertions below hold whether or not consent is read.
      device.emit(DVXRAnchorChanged(device.anchors.single,
          position: const DVVec3(1, 1, 1), orientation: DVQuat.identity));
      await _settle();
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.tracking);

      expect(device.calls, isNot(contains('xr.anchor.persist')));
      expect(await store.read('lobby-sign'), isNull);
      expect(session.isPersisted('n0'), isFalse);
      await xr.dispose();
    });

    test('with consent it is persisted as the OS token, never as a pose', () async {
      consent.allowed = <DVSpatialDataUse>{DVSpatialDataUse.persistAnchors};
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      await session.attach(DVSceneGraph(scene(<DVAnchor>[const DVAnchor.world(id: 'lobby-sign')])));
      device.emit(DVXRAnchorChanged(device.anchors.single,
          position: const DVVec3(3.25, 1.5, -7.75), orientation: DVQuat.identity));
      await _settle();

      final String? token = await store.read('lobby-sign');
      expect(token, isNotNull);
      expect(token, isNot(contains('3.25')));
      expect(session.isPersisted('n0'), isTrue);
      await xr.dispose();
    });

    test('consent withdrawn between launches: the stored anchor is not resolved or kept', () async {
      await store.write('lobby-sign', 'token-anchor-1');
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      await session.attach(DVSceneGraph(scene(<DVAnchor>[const DVAnchor.world(id: 'lobby-sign')])));
      expect(device.calls, isNot(contains('xr.anchor.resolve')));
      expect(await store.read('lobby-sign'), isNull);
      await xr.dispose();
    });

    test('a world anchor that does not re-localize reports DV-XR-003 and stays hidden', () async {
      consent.allowed = <DVSpatialDataUse>{DVSpatialDataUse.persistAnchors};
      await store.write('lobby-sign', 'token-from-last-launch');
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      final DVSceneGraph graph =
          DVSceneGraph(scene(<DVAnchor>[const DVAnchor.world(id: 'lobby-sign')]));
      await session.attach(graph);

      expect(device.calls, contains('xr.anchor.resolve'));
      expect(device.calls, isNot(contains('xr.anchor.create')),
          reason: 'a new anchor at a new place would be the drift the code exists to prevent');
      expect(session.codes, contains('DV-XR-003'));
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.notRelocalized);
      expect(graph.anchorPlacementOf('n0'), DVSceneAnchorPlacement.hidden);
      await xr.dispose();
    });

    test('one that does re-localize is resolved, not created again', () async {
      consent.allowed = <DVSpatialDataUse>{DVSpatialDataUse.persistAnchors};
      device = DVXRFakeDevice(relocalizable: <String>{'token-kept'});
      await store.write('lobby-sign', 'token-kept');
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      await session.attach(DVSceneGraph(scene(<DVAnchor>[const DVAnchor.world(id: 'lobby-sign')])));
      expect(device.calls, contains('xr.anchor.resolve'));
      expect(device.calls, isNot(contains('xr.anchor.create')));
      expect(session.codes, isNot(contains('DV-XR-003')));
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.searching);
      await xr.dispose();
    });

    test('backgrounding hides every anchor; resuming looks for them again', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      final DVSceneGraph graph =
          DVSceneGraph(scene(<DVAnchor>[const DVAnchor.plane(DVPlane.horizontal)]));
      await session.attach(graph);
      device.emit(DVXRAnchorChanged(device.anchors.single,
          position: DVVec3.zero, orientation: DVQuat.identity));
      await _settle();
      expect(graph.anchorPlacementOf('n0'), DVSceneAnchorPlacement.located);

      lifecycle.set(DVAppLifecycle.backgrounded);
      await _settle();
      expect(graph.anchorPlacementOf('n0'), DVSceneAnchorPlacement.hidden);

      lifecycle.set(DVAppLifecycle.ready);
      await _settle();
      expect(device.calls.where((String c) => c == 'xr.anchor.create'), hasLength(2));
      expect(session.anchorStatus('n0'), DVSpatialAnchorStatus.searching);
      await xr.dispose();
    });
  });

  group('input', () {
    DV3DSceneDocument buttons() => DV3DSceneDocument(
          id: 'panel',
          nodes: <DVSceneNodeData>[
            DVSceneNodeData.group(
              id: 'card',
              transform: DVTransform(translation: const DVVec3(0, 1, -2)),
              children: <DVSceneNodeData>[
                DVSceneNodeData.mesh(
                  id: 'buy',
                  primitive: const DVScenePrimitive.box(DVVec3(0.5, 0.5, 0.1)),
                ),
              ],
            ),
          ],
        );

    test('a hand ray selects the node it hits, bubbling to the nearest handler', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      final List<String> taps = <String>[];
      await session.attach(DVSceneGraph(buttons()),
          onTap: <String, void Function()>{'card': () => taps.add('card')});

      device.emit(DVXRInput(DVSpatialInputEvent.ray(
          DVSpatialInputAction.select, DVSpatialInputSource.hand,
          origin: const DVVec3(0, 1, 0), direction: const DVVec3(0, 0, -1))));
      await _settle();
      expect(taps, <String>['card']);
      await xr.dispose();
    });

    test('rays are converted from the device convention before picking', () async {
      device = DVXRFakeDevice(
        convention: const DVSpatialConvention(handedness: DVSceneHandedness.left),
      );
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      final List<String> grabs = <String>[];
      await session.attach(DVSceneGraph(buttons()),
          onGrab: <String, void Function()>{'buy': () => grabs.add('buy')});

      // Forward in a left-handed device is +Z.
      device.emit(DVXRInput(DVSpatialInputEvent.ray(
          DVSpatialInputAction.grab, DVSpatialInputSource.controller,
          origin: const DVVec3(0, 1, 0), direction: const DVVec3(0, 0, 1))));
      await _settle();
      expect(grabs, <String>['buy']);
      await xr.dispose();
    });

    test('gaze arrives as a selected node, never as a ray', () async {
      expect(
        () => DVSpatialInputEvent.ray(DVSpatialInputAction.select, DVSpatialInputSource.gaze,
            origin: DVVec3.zero, direction: const DVVec3(0, 0, -1)),
        throwsArgumentError,
      );

      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      final List<String> released = <String>[];
      await session.attach(DVSceneGraph(buttons()),
          onRelease: <String, void Function()>{'buy': () => released.add('buy')});
      device.emit(DVXRInput(DVSpatialInputEvent.target(
          DVSpatialInputAction.release, DVSpatialInputSource.gaze, 'buy')));
      await _settle();
      expect(released, <String>['buy']);
      await xr.dispose();
    });
  });

  group('frames and comfort', () {
    test('a sustained drop below the target reports DV-XR-007 once', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      for (int i = 0; i < 200; i++) {
        device.emit(const DVXRFrameTimed(Duration(milliseconds: 20)));
      }
      await _settle();
      expect(session.codes.where((String c) => c == 'DV-XR-007'), hasLength(1));
      await xr.dispose();
    });

    test('an immersive space applies the comfort policy it was given', () async {
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(const DVSpatialSpaceRequest(
        kind: DVSpatialSpaceKind.immersive,
        route: '/tour',
        comfort: DVComfortOptions(locomotion: <DVLocomotion>{DVLocomotion.smooth}),
      )))
          .session!;
      expect(session.comfort.vignette, isTrue);
      expect(session.codes, contains('DV-XR-005'));
      await xr.dispose();
    });
  });

  group('what never reaches a report', () {
    test('no pose, anchor position or light probe appears in any diagnostic', () async {
      consent.allowed = <DVSpatialDataUse>{DVSpatialDataUse.persistAnchors};
      device = DVXRFakeDevice(failing: <String>{'xr.environment.probe'});
      await store.write('gone', 'token-stale');
      final DVXRRuntime xr = runtime();
      final DVSpatialSession session = (await xr.present(_passthrough)).session!;
      await session.attach(DVSceneGraph(DV3DSceneDocument(id: 's', nodes: <DVSceneNodeData>[
        DVSceneNodeData(
          id: 'a',
          kind: DVSceneNodeKind.group,
          anchor: const DVAnchor.world(id: 'gone'),
        ),
        DVSceneNodeData(
          id: 'b',
          kind: DVSceneNodeKind.group,
          anchor: const DVAnchor.world(id: 'fresh'),
        ),
      ])));
      device.emit(const DVXRHeadPoseChanged(DVVec3(4.125, 1.625, -9.375), DVQuat.identity));
      device.emit(DVXRAnchorChanged(device.anchors.last,
          position: const DVVec3(6.875, 0.4375, 2.5625), orientation: DVQuat.identity));
      for (int i = 0; i < 300; i++) {
        device.emit(const DVXRFrameTimed(Duration(milliseconds: 25)));
      }
      device.emit(const DVXRPermissionRevoked('camera'));
      await _settle();

      expect(session.headPose, isNotNull);
      expect(reports, isNotEmpty);
      final String all = reports.join('\n');
      for (final String number in <String>['4.125', '1.625', '9.375', '6.875', '0.4375', '2.5625']) {
        expect(all, isNot(contains(number)));
      }
      await xr.dispose();
    });
  });

  test('the head pose converts, and a frame view comes from it', () async {
    device = DVXRFakeDevice(
      convention: const DVSpatialConvention(handedness: DVSceneHandedness.left),
    );
    final DVXRRuntime xr = runtime();
    final DVSpatialSession session = (await xr.present(_volume)).session!;
    expect(session.view(), isNull, reason: 'no pose yet, no view invented');
    device.emit(const DVXRHeadPoseChanged(DVVec3(0, 1.6, 1), DVQuat.identity));
    await _settle();
    expect(session.headPose!.position.z, closeTo(-1, 1e-9));
    expect(session.view()!.eye.z, closeTo(-1, 1e-9));
    await xr.dispose();
  });

  test('every device call is a declared binding name', () async {
    final DVXRRuntime xr = runtime();
    final DVSpatialSession session = (await xr.present(_passthrough)).session!;
    await session.attach(DVSceneGraph(DV3DSceneDocument(id: 's', nodes: <DVSceneNodeData>[
      DVSceneNodeData(id: 'a', kind: DVSceneNodeKind.group, anchor: const DVAnchor.world(id: 'w')),
    ])));
    await xr.dispose();
    expect(device.calls.toSet().difference(DVXRDevice.bindingNames), isEmpty);
    unawaited(Future<void>.value());
  });

  group('when a token cannot be kept', () {
    late DVMemoryLogSink logs;

    DV3DSceneDocument scene(List<DVAnchor> anchors) => DV3DSceneDocument(
          id: 'shop',
          nodes: <DVSceneNodeData>[
            for (int i = 0; i < anchors.length; i++)
              DVSceneNodeData(
                id: 'n$i',
                kind: DVSceneNodeKind.mesh,
                primitive: const DVScenePrimitive.box(DVVec3(0.1, 0.1, 0.1)),
                anchor: anchors[i],
              ),
          ],
        );

    setUp(() {
      logs = DVMemoryLogSink();
      DVObservability.useLogging(sinks: <DVLogSink>[logs]);
    });
    tearDown(DVObservability.resetLogging);

    test('a store that refuses it leaves the anchor unpersisted, and says so without the token',
        () async {
      consent.allowed = <DVSpatialDataUse>{DVSpatialDataUse.persistAnchors};
      final DVXRRuntime xr = DVXRRuntime(
        device: device,
        capability: DVSpatialCapability.headset(),
        permissions: permissions,
        lifecycle: lifecycle,
        consent: consent,
        anchorStore: _RefusingAnchorStore(),
        diagnostics: (String code, String message, Map<String, Object?> context) =>
            reports.add(_Report(code, message, context)),
      );
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      await session.attach(DVSceneGraph(scene(<DVAnchor>[const DVAnchor.world(id: 'lobby-sign')])));
      device.emit(DVXRAnchorChanged(device.anchors.single,
          position: const DVVec3(1, 1, 1), orientation: DVQuat.identity));
      await _settle();

      expect(device.calls, contains('xr.anchor.persist'),
          reason: 'the store is only reached once the OS has handed over a token');
      expect(session.isPersisted('n0'), isFalse,
          reason: 'nothing was stored, so claiming otherwise would stop the next attempt');
      final List<DVLogRecord> errors = <DVLogRecord>[
        for (final DVLogRecord r in logs.records)
          if (r.level == DVLogLevel.error) r,
      ];
      expect(errors, hasLength(1));
      expect(errors.single.context['anchor'], 'lobby-sign');
      expect(errors.single.toJsonLine(), isNot(contains('token-')));
      await xr.dispose();
    });

    test('consent withdrawn while the OS persists: the token it hands back is not stored', () async {
      consent.allowed = <DVSpatialDataUse>{DVSpatialDataUse.persistAnchors};
      final _HeldPersist held = _HeldPersist(device);
      final DVXRRuntime xr = runtime(withDevice: held);
      final DVSpatialSession session = (await xr.present(_volume)).session!;
      await session.attach(DVSceneGraph(scene(<DVAnchor>[const DVAnchor.world(id: 'lobby-sign')])));
      device.emit(DVXRAnchorChanged(device.anchors.single,
          position: const DVVec3(1, 1, 1), orientation: DVQuat.identity));
      await _settle();
      expect(held.persisting, isTrue);

      consent.allowed = const <DVSpatialDataUse>{};
      held.release();
      await _settle();

      expect(await store.read('lobby-sign'), isNull);
      expect(session.isPersisted('n0'), isFalse);
      await xr.dispose();
    });
  });
}

/// A store with no key to write under.
final class _RefusingAnchorStore implements DVSpatialAnchorStore {
  @override
  Future<String?> read(String id) async => null;

  @override
  Future<void> write(String id, String token) async =>
      throw StateError('the key store is locked');

  @override
  Future<void> remove(String id) async {}

  @override
  Future<List<String>> ids() async => const <String>[];
}

/// The fake device, with `xr.anchor.persist` held open until [release].
final class _HeldPersist implements DVXRDevice {
  _HeldPersist(this.inner);

  final DVXRFakeDevice inner;
  final Completer<void> _gate = Completer<void>();
  bool persisting = false;

  void release() => _gate.complete();

  @override
  DVSpatialConvention get convention => inner.convention;

  @override
  Future<DVSpatialCapability?> queryCapability() => inner.queryCapability();

  @override
  Future<String?> openSession() => inner.openSession();

  @override
  Future<void> closeSession(String session) => inner.closeSession(session);

  @override
  Future<String?> openSpace(String session, DVSpatialSpaceRequest request) =>
      inner.openSpace(session, request);

  @override
  Future<void> closeSpace(String space) => inner.closeSpace(space);

  @override
  Future<void> setPassthrough(String space, bool enabled) => inner.setPassthrough(space, enabled);

  @override
  Future<String?> createAnchor(String session, DVAnchor anchor) => inner.createAnchor(session, anchor);

  @override
  Future<String?> persistAnchor(String session, String anchor) async {
    persisting = true;
    await _gate.future;
    return inner.persistAnchor(session, anchor);
  }

  @override
  Future<String?> resolveAnchor(String session, String token) => inner.resolveAnchor(session, token);

  @override
  Future<DVSpatialLightProbe?> probeEnvironment(String session) => inner.probeEnvironment(session);

  @override
  Stream<DVXRDeviceEvent> observe(String session) => inner.observe(session);
}
