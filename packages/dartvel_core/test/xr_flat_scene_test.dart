// A scene written for space, presented flat.
//
// One page, three presentations: the scene written for a headset is the same
// scene a phone shows in a viewport. Two things in it cannot be honoured flat
// -- an anchor, and the passthrough environment -- and each has a code. The
// silent failures are a passthrough scene that refuses to start because
// "passthrough" was looked up as an asset, and anchored content drawn at the
// origin with nobody told.
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVMemoryLogSink logs;

  setUp(() {
    logs = DVMemoryLogSink();
    final DVLogger previous = DVObservability.logger;
    addTearDown(() => DVObservability.logger = previous);
    DVSceneRuntime.debugResetReports();
    DVObservability.logger = DVLogger(sinks: <DVLogSink>[logs]);
  });

  DV3DSceneDocument doc({String? environment = DV3DSceneDocument.passthroughEnvironment}) =>
      DV3DSceneDocument(
        id: 'tag-scene',
        environment: environment,
        nodes: <DVSceneNodeData>[
          DVSceneNodeData(
            id: 'price',
            kind: DVSceneNodeKind.mesh,
            primitive: const DVScenePrimitive.box(DVVec3(0.2, 0.1, 0.02)),
            anchor: const DVAnchor.plane(DVPlane.vertical),
          ),
        ],
      );

  DVSceneRuntime runtime(DV3DSceneDocument d, {bool inSpace = false}) => DVSceneRuntime(
        document: d,
        renderer: DVSceneRecordingRenderer(),
        loader: DVSceneAssetLoader(fetchers: const <DVSceneAssetSource, DVSceneAssetFetch>{}),
        presentsInSpace: inSpace,
      );

  List<String> codes() => <String>[
        for (final DVLogRecord r in logs.records)
          if (r.code != null) r.code!,
      ];

  test('passthrough is an environment a document may name, and round-trips', () {
    final DV3DSceneDocument d = doc();
    expect(DV3DSceneDocument.decode(d.encode()).environment, 'passthrough');
  });

  test('flat, a passthrough scene renders, lit by the studio, and says so once', () async {
    final DVSceneRuntime r = runtime(doc());
    expect(await r.start(), DV3DDegradation.none,
        reason: 'passthrough is not an asset to load');
    final DVSceneFrame first = r.frame(DVSceneView.orbit(distance: 3), 100, 100);
    r.frame(DVSceneView.orbit(distance: 3), 100, 100);

    expect(first.environment, DV3DSceneDocument.studioEnvironment);
    expect(codes().where((String c) => c == 'DV-XR-001'), hasLength(1));
    r.dispose();
  });

  test('flat, an anchored node is at the origin, drawn, and DV-XR-002 is reported once', () async {
    final DVSceneRuntime r = runtime(doc(environment: DV3DSceneDocument.studioEnvironment));
    await r.start();
    await r.update(doc(environment: DV3DSceneDocument.studioEnvironment));

    expect(r.graph.anchorPlacementOf('price'), DVSceneAnchorPlacement.origin);
    final DVSceneFrame frame = r.frame(DVSceneView.orbit(distance: 3), 100, 100);
    expect(frame.draws.map((DVSceneDraw d) => d.nodeId), contains('price'));
    expect(codes().where((String c) => c == 'DV-XR-002'), hasLength(1));
    expect(codes(), isNot(contains('DV-XR-001')));
    r.dispose();
  });

  test('in space, neither is reported: the session places anchors and lights the scene', () async {
    final DVSceneRuntime r = runtime(doc(), inSpace: true);
    await r.start();
    final DVSceneFrame frame = r.frame(DVSceneView.orbit(distance: 3), 100, 100);
    expect(frame.environment, DV3DSceneDocument.passthroughEnvironment);
    expect(codes(), isNot(contains('DV-XR-001')));
    expect(codes(), isNot(contains('DV-XR-002')));
    r.dispose();
  });
}
