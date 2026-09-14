// Anchors, grab and release on scene nodes, and the passthrough environment.
//
// One page, three presentations: the modifiers a scene written for a headset
// uses must resolve into the document every presentation reads, and a phone
// showing that scene flat must draw it and say what it could not honour --
// not refuse to render, and not render quietly with the sign at the origin.
import 'package:dartvel_core/dartvel.dart'
    show DVLogRecord, DVLogSink, DVLogger, DVMemoryLogSink, DVObservability;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolving', () {
    test('an anchor is typed data on the node it modifies', () {
      final DVSceneResolved resolved = DVScene(nodes: <DVSceneNode>[
        DVMesh.box(const DVVec3(0.2, 0.1, 0.02))
            .id('price')
            .anchor(const DVAnchor.plane(DVPlane.vertical)),
        DVMesh.sphere(0.1).id('free'),
      ]).resolve();

      expect(resolved.document.find('price')!.anchor, const DVAnchor.plane(DVPlane.vertical));
      expect(resolved.document.find('free')!.anchor, isNull);
    });

    test('grab and release handlers are collected by node id, apart from taps', () {
      final List<String> seen = <String>[];
      final DVSceneResolved resolved = DVScene(nodes: <DVSceneNode>[
        DVMesh.box(const DVVec3(1, 1, 1))
            .id('crate')
            .onGrab(() => seen.add('grab'))
            .onRelease(() => seen.add('release')),
      ]).resolve();

      expect(resolved.tapHandlers, isEmpty);
      resolved.grabHandlers['crate']!();
      resolved.releaseHandlers['crate']!();
      expect(seen, <String>['grab', 'release']);
    });

    test('the passthrough environment resolves to the document name for it', () {
      final DVSceneResolved resolved =
          const DVScene(environment: DVEnvironment.passthrough).resolve();
      expect(resolved.document.environment, DV3DSceneDocument.passthroughEnvironment);
      expect(resolved.document.assets, isEmpty);
    });
  });

  test('a grab handler fires from a hand ray in a spatial session', () async {
    final List<String> grabbed = <String>[];
    final DVSceneResolved resolved = DVScene(nodes: <DVSceneNode>[
      DVMesh.box(const DVVec3(0.5, 0.5, 0.5))
          .id('crate')
          .position(const DVVec3(0, 1, -2))
          .onGrab(() => grabbed.add('crate')),
    ]).resolve();
    final DVXRFakeDevice device = DVXRFakeDevice();
    final DVXRRuntime runtime = DVXRRuntime(
      device: device,
      capability: DVSpatialCapability.headset(),
      permissions: const _Granted(),
      diagnostics: (String c, String m, Map<String, Object?> x) {},
    );
    final DVSpatialSession session = (await runtime.present(const DVSpatialSpaceRequest(
      kind: DVSpatialSpaceKind.volume,
      route: '/crate',
    )))
        .session!;
    await session.attach(DVSceneGraph(resolved.document),
        onGrab: resolved.grabHandlers, onRelease: resolved.releaseHandlers);

    device.emit(DVXRInput(DVSpatialInputEvent.ray(
        DVSpatialInputAction.grab, DVSpatialInputSource.hand,
        origin: const DVVec3(0, 1, 0), direction: const DVVec3(0, 0, -1))));
    await Future<void>.delayed(Duration.zero);

    expect(grabbed, <String>['crate']);
    await runtime.dispose();
  });

  testWidgets('flat, an anchored passthrough scene draws, and reports both codes once',
      (WidgetTester tester) async {
    final DVMemoryLogSink logs = DVMemoryLogSink();
    final DVLogger previous = DVObservability.logger;
    DVObservability.logger = DVLogger(sinks: <DVLogSink>[logs]);
    addTearDown(() => DVObservability.logger = previous);
    DVSceneRuntime.debugResetReports();
    final DVSceneFake fake = DV.Test.fake3D();
    addTearDown(DVScene3D.reset);
    final DVSceneController controller = DVSceneController();

    Widget scene() => ProviderScope(
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: DVBox.scene(
                  DVScene(
                    environment: DVEnvironment.passthrough,
                    nodes: <DVSceneNode>[
                      DVMesh.box(const DVVec3(0.2, 0.1, 0.02))
                          .id('price')
                          .anchor(const DVAnchor.plane(DVPlane.vertical)),
                    ],
                  ),
                  controller: controller,
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(scene());
    for (int i = 0; i < 4; i++) {
      await tester.pump();
    }
    await tester.pumpWidget(scene());
    await tester.pump();

    expect(controller.isRendering, isTrue);
    expect(fake.last!.frames, isNotEmpty);
    expect(fake.last!.frames.last.environment, DV3DSceneDocument.studioEnvironment);
    final List<String> codes = <String>[
      for (final DVLogRecord r in logs.records)
        if (r.code != null) r.code!,
    ];
    expect(codes.where((String c) => c == 'DV-XR-001'), hasLength(1));
    expect(codes.where((String c) => c == 'DV-XR-002'), hasLength(1));
  });
}

final class _Granted implements DVCapturePermissions {
  const _Granted();

  @override
  Future<bool> request(String permission) async => true;
}
