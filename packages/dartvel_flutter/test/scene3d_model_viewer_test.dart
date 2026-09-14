// DVModel3DViewer: what a generated product.viewer3D() renders.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _glb() {
  final List<int> text = utf8.encode(jsonEncode(<String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
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
        'count': 3,
        'min': <double>[-0.5, -0.5, -0.5],
        'max': <double>[0.5, 0.5, 0.5],
      },
    ],
  }));
  final List<int> chunk = <int>[...text, for (int i = 0; i < (4 - text.length % 4) % 4; i++) 0x20];
  List<int> u32(int v) => <int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
  return <int>[
    ...u32(0x46546C67), ...u32(2), ...u32(20 + chunk.length),
    ...u32(chunk.length), ...u32(0x4E4F534A), ...chunk,
  ];
}

Widget _host(Widget child) => MaterialApp(
      home: Center(child: SizedBox(width: 320, height: 180, child: child)),
    );

void main() {
  final List<int> bytes = _glb();
  late DVSceneAsset asset;
  late DVSceneFake fake;

  setUp(() async {
    DV.FileStorage.configure(DVMemoryFileStorageAdapter());
    asset = const DVModel3DFieldPolicy()
        .accept(bytes, storageKey: 'tenants/default/products/p.glb');
    await DV.FileStorage.put(asset.reference, bytes);
    DVSceneRuntime.debugResetReports();
    fake = DV.Test.fake3D();
  });

  tearDown(DVScene3D.reset);

  testWidgets('renders the model with an orbit camera the user can turn',
      (WidgetTester tester) async {
    final DVSceneController controller = DVSceneController();
    await tester.pumpWidget(_host(DVModel3DViewer(asset, controller: controller)));
    for (int i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(controller.isRendering, isTrue);
    expect(fake.last!.frames.last.draws.single.nodeId, 'model');
    expect(fake.last!.frames.last.environment, DV3DSceneDocument.studioEnvironment);

    await tester.drag(find.byType(DVSceneViewport), const Offset(100, 0));
    await tester.pump();
    expect(controller.view!.yaw, isNot(0));
  });

  testWidgets("where the target cannot render, the field's poster is shown",
      (WidgetTester tester) async {
    DVScene3D.reset();
    final DVSceneAsset withPoster = DVSceneAsset(
      kind: asset.kind,
      source: asset.source,
      reference: asset.reference,
      sha256: asset.sha256,
      poster: const DVImage.asset('assets/posters/p.png'),
    );
    await tester.pumpWidget(_host(DVModel3DViewer(withPoster)));
    await tester.pump();
    await tester.pump();

    final DVImageView poster = tester.widget<DVImageView>(find.byType(DVImageView));
    expect(poster.image, withPoster.poster);
  });

  testWidgets('an empty field renders nothing rather than an empty viewport',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const DVModel3DViewer(null)));
    expect(find.byType(DVSceneViewport), findsNothing);
    expect(fake.renderers, isEmpty);
  });
}
