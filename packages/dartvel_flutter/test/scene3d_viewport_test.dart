// DVBox.scene: where the widget tree and the scene graph meet.
//
// Rendered here against DV.Test.fake3D(), the headless backend, because no
// GPU exists under flutter_test. What is checked is everything that is the
// viewport's own job whatever renderer draws: a signal moves a node without
// restarting the scene, a tap reaches the node under the pointer and not a
// node behind another, the poster replaces the scene and says why, and
// removing the box releases what the scene uploaded.
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartvel_core/src/observability/observability.dart'
    show DVLogRecord, DVObservability;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A GLB holding one triangle mesh with bounds -1..1 on every axis.
List<int> _cubeGlb() {
  final Map<String, Object?> json = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'scenes': <Object?>[
      <String, Object?>{'nodes': <int>[0]},
    ],
    'nodes': <Object?>[
      <String, Object?>{'mesh': 0},
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{'POSITION': 0},
          },
        ],
      },
    ],
    'accessors': <Object?>[
      <String, Object?>{
        'count': 36,
        'type': 'VEC3',
        'componentType': 5126,
        'min': <double>[-1, -1, -1],
        'max': <double>[1, 1, 1],
      },
    ],
  };
  final List<int> text = utf8.encode(jsonEncode(json));
  final List<int> chunk = <int>[...text, for (int i = 0; i < (4 - text.length % 4) % 4; i++) 0x20];
  List<int> u32(int v) => <int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  return <int>[
    ...u32(0x46546C67), ...u32(2), ...u32(12 + 8 + chunk.length),
    ...u32(chunk.length), ...u32(0x4E4F534A), ...chunk,
  ];
}

final List<int> _cube = _cubeGlb();

DVSceneAsset _stored(String name) => DVSceneAsset(
      kind: DVSceneAssetKind.model,
      source: DVSceneAssetSource.stored,
      reference: 'tenants/default/models/$name.glb',
      sha256: crypto.sha256.convert(_cube).toString(),
    );

Widget _host(Widget child, {double width = 400, double height = 225}) =>
    ProviderScope(
      child: MaterialApp(
        home: Center(
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    );

/// Flushes asset loads, which complete in microtasks against memory storage.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump();
  }
}

/// The global position where [nodeId] is drawn.
Offset _screenOf(WidgetTester tester, DVSceneController controller, String nodeId) {
  final Size size = tester.getSize(find.byType(DVSceneViewport));
  final DVVec3 at = controller.view!.project(
      controller.runtime!.graph.worldPosition(nodeId), size.width, size.height)!;
  return tester.getTopLeft(find.byType(DVSceneViewport)) + Offset(at.x, at.y);
}

List<DVLogRecord> _posterReports() => DVObservability.recentLogs
    .where((DVLogRecord r) => r.code == 'DV-3D-001')
    .toList();

void main() {
  late DVSceneFake fake;

  setUp(() async {
    DV.FileStorage.configure(DVMemoryFileStorageAdapter());
    await DV.FileStorage.put('tenants/default/models/kart.glb', _cube);
    DVSceneRuntime.debugResetReports();
    DVObservability.resetLogging();
    fake = DV.Test.fake3D();
  });

  tearDown(DVScene3D.reset);

  testWidgets('a scene whose assets load renders through the configured backend',
      (WidgetTester tester) async {
    final DVSceneController controller = DVSceneController();
    await tester.pumpWidget(_host(DVBox.scene(
      DVScene(nodes: <DVSceneNode>[
        DVModel3D(_stored('kart')).id('kart'),
        DVSceneCamera.orbit(distance: 6),
        DVLight.directional(direction: const DVVec3(-1, -2, -1)).shadows(),
      ]),
      controller: controller,
    )));
    await _settle(tester);

    expect(controller.degradation, DV3DDegradation.none);
    expect(controller.isRendering, isTrue);
    final DVSceneRecordingRenderer renderer = fake.last!;
    expect(renderer.frames, isNotEmpty);
    expect(renderer.frames.last.draws.single.nodeId, 'kart');
    expect(renderer.frames.last.lights.single.light.castShadows, isTrue);
    expect(find.byType(DVImageView), findsNothing);
  });

  group('the poster contract', () {
    testWidgets('with no renderer on the target, the poster is shown and says why',
        (WidgetTester tester) async {
      DVScene3D.reset();
      final DVSceneController a = DVSceneController();
      final DVSceneController b = DVSceneController();
      DVScene scene() => DVScene(
            poster: const DVImage.asset('assets/posters/kart.png'),
            nodes: <DVSceneNode>[DVModel3D(_stored('kart'))],
          );
      await tester.pumpWidget(_host(Column(children: <Widget>[
        Expanded(child: DVBox.scene(scene(), controller: a)),
        Expanded(child: DVBox.scene(scene(), controller: b)),
      ])));
      await _settle(tester);

      expect(a.degradation, DV3DDegradation.unsupportedTarget);
      expect(b.degradation, DV3DDegradation.unsupportedTarget);
      expect(find.byType(DVImageView), findsNWidgets(2));
      // Once per boot, not once per viewport.
      expect(_posterReports(), hasLength(1));
    });

    testWidgets('a missing asset shows the poster rather than a scene with a hole',
        (WidgetTester tester) async {
      final DVSceneController controller = DVSceneController();
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(
          poster: const DVImage.asset('assets/posters/kart.png'),
          nodes: <DVSceneNode>[
            DVModel3D(_stored('kart')),
            DVModel3D(_stored('gone')),
          ],
        ),
        controller: controller,
      )));
      await _settle(tester);

      expect(controller.degradation, DV3DDegradation.assetMissing);
      expect(controller.failedAssets, hasLength(1));
      expect(find.byType(DVImageView), findsOneWidget);
      expect(fake.last!.frames, isEmpty);
      expect(fake.last!.live, isEmpty);
    });

    testWidgets('with no poster at all the box still renders something labelled',
        (WidgetTester tester) async {
      DVScene3D.reset();
      final SemanticsHandle semantics = tester.ensureSemantics();
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(label: 'Espresso M3', nodes: <DVSceneNode>[DVModel3D(_stored('kart'))]),
      )));
      await _settle(tester);

      expect(find.bySemanticsLabel(RegExp('Espresso M3')), findsOneWidget);
      expect(tester.getSize(find.byType(DVSceneViewport)), const Size(400, 225));
      semantics.dispose();
    });
  });

  group('signals', () {
    testWidgets('a signal-valued position moves the node without restarting the scene',
        (WidgetTester tester) async {
      final DVSceneController controller = DVSceneController();
      late DVSignal<DVVec3> position;
      late DVSignal<double> angle;
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        position = context.signal(DVVec3.zero);
        angle = context.signal(0.0);
        return DVBox.scene(
          DVScene(nodes: <DVSceneNode>[
            DVModel3D(_stored('kart')).id('kart').position(position).rotationY(angle),
          ]),
          controller: controller,
        );
      })));
      await _settle(tester);
      final DVSceneRuntime runtime = controller.runtime!;
      final int uploads = fake.last!.uploads.length;

      position.value = const DVVec3(1.5, 0, 0);
      angle.value = 0.5;
      await tester.pump();

      expect(controller.runtime, same(runtime));
      expect(runtime.graph.worldPosition('kart'), const DVVec3(1.5, 0, 0));
      expect(runtime.graph.transformOf('kart').rotation,
          DVQuat.axisAngle(const DVVec3(0, 1, 0), 0.5));
      expect(fake.last!.uploads, hasLength(uploads));
      expect(fake.last!.frames.last.draws.single.world.translation,
          const DVVec3(1.5, 0, 0));
    });

    testWidgets('a modifier given something that is neither a value nor a signal fails at once',
        (WidgetTester tester) async {
      expect(() => DVMesh.box(DVVec3.one).position('left'), throwsArgumentError);
      expect(() => DVMesh.box(DVVec3.one).visible(1), throwsArgumentError);
    });
  });

  group('taps', () {
    testWidgets('a tap reaches the node drawn under it, and follows the node when it moves',
        (WidgetTester tester) async {
      final DVSceneController controller = DVSceneController();
      int taps = 0;
      late DVSignal<DVVec3> position;
      await tester.pumpWidget(_host(Builder(builder: (BuildContext context) {
        position = context.signal(const DVVec3(1, 0.5, 0));
        return DVBox.scene(
          DVScene(nodes: <DVSceneNode>[
            DVMesh.sphere(0.3).id('ball').position(position).onTap(() => taps++),
            DVSceneCamera.orbit(distance: 5),
          ]),
          controller: controller,
        );
      })));
      await _settle(tester);

      final Offset before = _screenOf(tester, controller, 'ball');
      await tester.tapAt(before);
      expect(taps, 1);

      position.value = const DVVec3(-1, -0.5, 0);
      await tester.pump();
      await tester.tapAt(before);
      expect(taps, 1, reason: 'the old place is empty now');

      await tester.tapAt(_screenOf(tester, controller, 'ball'));
      expect(taps, 2);
    });

    testWidgets('a node in front blocks a tap from reaching the one behind it',
        (WidgetTester tester) async {
      final DVSceneController controller = DVSceneController();
      int behind = 0;
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(nodes: <DVSceneNode>[
          DVMesh.box(const DVVec3(1, 1, 0.1)).id('target').onTap(() => behind++),
          DVMesh.box(const DVVec3(2, 2, 0.1)).id('wall').position(const DVVec3(0, 0, 1)),
          DVSceneCamera.orbit(distance: 5),
        ]),
        controller: controller,
      )));
      await _settle(tester);

      await tester.tapAt(_screenOf(tester, controller, 'target'));
      expect(behind, 0);
    });

    testWidgets("a tap on a child without a handler reaches its group's handler",
        (WidgetTester tester) async {
      final DVSceneController controller = DVSceneController();
      int group = 0;
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(nodes: <DVSceneNode>[
          DVNode(children: <DVSceneNode>[
            DVMesh.sphere(0.4).id('wheel'),
          ]).id('kart').onTap(() => group++),
          DVSceneCamera.orbit(distance: 5),
        ]),
        controller: controller,
      )));
      await _settle(tester);

      await tester.tapAt(_screenOf(tester, controller, 'wheel'));
      expect(group, 1);
    });
  });

  group('lifetime and identity', () {
    testWidgets('removing the box releases everything the scene uploaded',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(nodes: <DVSceneNode>[DVModel3D(_stored('kart'))]),
      )));
      await _settle(tester);
      final DVSceneRecordingRenderer renderer = fake.last!;
      expect(renderer.live, hasLength(1));

      await tester.pumpWidget(_host(const SizedBox()));

      expect(renderer.live, isEmpty);
      expect(renderer.disposed, isTrue);
    });

    testWidgets('nodes without ids get the same ids on every build',
        (WidgetTester tester) async {
      final DVSceneController controller = DVSceneController();
      Widget build() => _host(DVBox.scene(
            DVScene(nodes: <DVSceneNode>[
              DVNode(children: <DVSceneNode>[DVMesh.sphere(1)]),
              DVModel3D(_stored('kart')),
            ]),
            controller: controller,
          ));
      await tester.pumpWidget(build());
      await _settle(tester);
      final DVSceneRuntime runtime = controller.runtime!;
      expect(runtime.graph.ids, <String>['node#0', 'node#0/mesh#0', 'model3d#1']);

      await tester.pumpWidget(build());
      await _settle(tester);

      expect(controller.runtime, same(runtime));
      expect(runtime.graph.ids, <String>['node#0', 'node#0/mesh#0', 'model3d#1']);
      expect(fake.last!.uploads, hasLength(1));
    });

    testWidgets('two nodes given one id is an error, not a merge',
        (WidgetTester tester) async {
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(nodes: <DVSceneNode>[
          DVMesh.sphere(1).id('same'),
          DVMesh.sphere(1).id('same'),
        ]),
      )));
      expect(tester.takeException(), isA<DV3DSceneFormatException>());
    });

    testWidgets('a scene that gains a model loads it and keeps the one it had',
        (WidgetTester tester) async {
      await DV.FileStorage.put('tenants/default/models/crate.glb', _cube);
      final DVSceneController controller = DVSceneController();
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(nodes: <DVSceneNode>[DVModel3D(_stored('kart')).id('kart')]),
        controller: controller,
      )));
      await _settle(tester);
      final DVSceneResource kart = fake.last!.live.single;

      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(nodes: <DVSceneNode>[
          DVModel3D(_stored('kart')).id('kart'),
          DVModel3D(_stored('crate')).id('crate'),
        ]),
        controller: controller,
      )));
      await _settle(tester);

      expect(controller.isRendering, isTrue);
      expect(fake.last!.live, hasLength(2));
      expect(fake.last!.live, contains(kart));
    });
  });

  group('orbit controls', () {
    Future<DVSceneController> drag(WidgetTester tester, {required bool controls}) async {
      final DVSceneController controller = DVSceneController();
      await tester.pumpWidget(_host(DVBox.scene(
        DVScene(nodes: <DVSceneNode>[
          DVMesh.sphere(1),
          DVSceneCamera.orbit(distance: 5, controls: controls),
        ]),
        controller: controller,
      )));
      await _settle(tester);
      await tester.drag(find.byType(DVSceneViewport), const Offset(120, 0));
      await tester.pump();
      return controller;
    }

    testWidgets('a camera with controls turns when dragged', (WidgetTester tester) async {
      final DVSceneController controller = await drag(tester, controls: true);
      expect(controller.view!.yaw, isNot(0));
    });

    testWidgets('a camera without controls does not', (WidgetTester tester) async {
      final DVSceneController controller = await drag(tester, controls: false);
      expect(controller.view!.yaw, 0);
    });
  });
}
