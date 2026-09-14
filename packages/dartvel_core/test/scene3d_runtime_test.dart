// The scene runtime between a document and a renderer adapter.
//
// What must never happen quietly: a scene drawn with a model missing, a GPU
// resource uploaded and never released, a resource released twice or drawn
// after release, draw order that changes between runs, and a poster shown
// without anyone being told why.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'scene3d_fixtures.dart';

void main() {
  final List<int> kart = glb(kartGltf());

  DVSceneAsset model(String key) => DVSceneAsset(
        kind: DVSceneAssetKind.model,
        source: DVSceneAssetSource.stored,
        reference: 'tenants/acme/$key.glb',
        sha256: sha256Hex(kart),
      );

  DV3DSceneDocument doc({bool mirrored = false, List<String> models = const <String>['kart']}) =>
      DV3DSceneDocument(
        id: 'showroom',
        handedness: mirrored ? DVSceneHandedness.left : DVSceneHandedness.right,
        assets: <String, DVSceneAsset>{
          for (final String m in models) m: model(m),
        },
        nodes: <DVSceneNodeData>[
          for (final String m in models) ...<DVSceneNodeData>[
            DVSceneNodeData.model(
                id: '$m-a',
                asset: m,
                transform: DVTransform(translation: const DVVec3(0, 0, -5))),
            DVSceneNodeData.model(id: '$m-b', asset: m),
          ],
          DVSceneNodeData.mesh(
              id: 'floor', primitive: DVScenePrimitive.plane(10, 10), visible: false),
          DVSceneNodeData.light(
              id: 'sun',
              light: const DVSceneLight.directional(direction: DVVec3(0, -1, 0))),
        ],
      );

  late Map<String, List<int>> store;
  late List<String> fetched;
  late DVSceneRecordingRenderer renderer;

  DVSceneAssetLoader loader() => DVSceneAssetLoader(
        tenant: () => 'acme',
        fetchers: <DVSceneAssetSource, DVSceneAssetFetch>{
          DVSceneAssetSource.stored: (DVSceneAsset a) async {
            fetched.add(a.reference);
            return store[a.reference];
          },
        },
      );

  List<DVLogRecord> posterReports() => DVObservability.recentLogs
      .where((DVLogRecord r) => r.code == 'DV-3D-001')
      .toList();

  setUp(() {
    store = <String, List<int>>{
      'tenants/acme/kart.glb': kart,
      'tenants/acme/crate.glb': kart,
    };
    fetched = <String>[];
    renderer = DVSceneRecordingRenderer();
    DVSceneRuntime.debugResetReports();
    DVObservability.resetLogging();
  });

  test('a scene whose assets load renders, one upload per asset', () async {
    final DVSceneRuntime runtime =
        DVSceneRuntime(document: doc(), renderer: renderer, loader: loader());
    expect(await runtime.start(), DV3DDegradation.none);
    expect(renderer.uploads.map((DVSceneResource r) => r.assetKey), <String>['kart']);
    expect(runtime.liveResources, 1);
  });

  test('the frame draws visible nodes in document order with world matrices',
      () async {
    final DVSceneRuntime runtime =
        DVSceneRuntime(document: doc(models: <String>['kart', 'crate']),
            renderer: renderer, loader: loader());
    await runtime.start();
    final DVSceneFrame frame = runtime.frame(
        DVSceneView.orbit(target: DVVec3.zero, distance: 3), 640, 360);

    expect(frame.draws.map((DVSceneDraw d) => d.nodeId),
        <String>['kart-a', 'kart-b', 'crate-a', 'crate-b']);
    expect(frame.draws.first.world, runtime.graph.worldMatrix('kart-a'));
    expect(frame.draws.first.resource, frame.draws[1].resource);
    expect(frame.lights.single.nodeId, 'sun');
    expect(renderer.frames, hasLength(1));
  });

  test('a mirrored document tells the renderer to flip its winding', () async {
    final DVSceneRuntime runtime = DVSceneRuntime(
        document: doc(mirrored: true), renderer: renderer, loader: loader());
    await runtime.start();
    expect(runtime.frame(DVSceneView.orbit(distance: 3), 10, 10).mirrored, isTrue);
  });

  test('a loaded model is picked by the bounds its file declared', () async {
    final DVSceneRuntime runtime =
        DVSceneRuntime(document: doc(), renderer: renderer, loader: loader());
    await runtime.start();
    // The model spans x -1..5, y 0..3, z -1..2. kart-a sits at z = -5, so
    // from z = -20 looking toward +Z it is met before kart-b at the origin.
    expect(
      runtime.graph.pick(const DVRay(DVVec3(4, 2, -20), DVVec3(0, 0, 1)))?.nodeId,
      'kart-a',
    );
    // Outside the file's bounds is empty space, not a default-sized box.
    expect(
      runtime.graph.pick(const DVRay(DVVec3(6, 2, -20), DVVec3(0, 0, 1))),
      isNull,
    );
  });

  group('degradation', () {
    test('a missing asset presents the poster instead of a scene with a hole',
        () async {
      store.remove('tenants/acme/crate.glb');
      final DVSceneRuntime runtime = DVSceneRuntime(
          document: doc(models: <String>['kart', 'crate']),
          renderer: renderer,
          loader: loader());

      expect(await runtime.start(), DV3DDegradation.assetMissing);
      expect(runtime.degradation, DV3DDegradation.assetMissing);
      expect(runtime.failedAssets, <String>['crate']);
      expect(() => runtime.frame(DVSceneView.orbit(distance: 3), 10, 10),
          throwsStateError);
      expect(renderer.frames, isEmpty);
      // What was uploaded before the failure is not left on the GPU.
      expect(renderer.live, isEmpty);
      expect(posterReports().single.context['asset'], 'crate');
    });

    test('no renderer on this target is unsupportedTarget, and nothing is fetched',
        () async {
      final DVSceneRuntime runtime =
          DVSceneRuntime(document: doc(), renderer: null, loader: loader());
      expect(await runtime.start(), DV3DDegradation.unsupportedTarget);
      expect(fetched, isEmpty);
    });

    test('scene3d disabled never touches the renderer', () async {
      final DVSceneRuntime runtime = DVSceneRuntime(
          document: doc(), renderer: renderer, loader: loader(), enabled: false);
      expect(await runtime.start(), DV3DDegradation.disabledByConfig);
      expect(renderer.initialized, isFalse);
    });

    test('a renderer that fails to initialise is gpuInitFailed', () async {
      final DVSceneRuntime runtime = DVSceneRuntime(
        document: doc(),
        renderer: DVSceneRecordingRenderer(initialization: DV3DDegradation.gpuInitFailed),
        loader: loader(),
      );
      expect(await runtime.start(), DV3DDegradation.gpuInitFailed);
      expect(fetched, isEmpty);
    });

    test('a renderer that throws while initialising is gpuInitFailed too',
        () async {
      final DVSceneRuntime runtime = DVSceneRuntime(
        document: doc(),
        renderer: DVSceneRecordingRenderer(initializationError: StateError('no device')),
        loader: loader(),
      );
      expect(await runtime.start(), DV3DDegradation.gpuInitFailed);
    });

    test('a target-wide cause is reported once per boot, however many viewports',
        () async {
      for (int i = 0; i < 3; i++) {
        await DVSceneRuntime(document: doc(), renderer: null, loader: loader()).start();
      }
      expect(posterReports(), hasLength(1));
      expect(posterReports().single.level, DVLogLevel.info);
      expect(posterReports().single.context['degradation'], 'unsupportedTarget');
    });

    test('each missing asset is reported once, not only the first', () async {
      store.clear();
      await DVSceneRuntime(document: doc(), renderer: renderer, loader: loader()).start();
      await DVSceneRuntime(document: doc(), renderer: DVSceneRecordingRenderer(), loader: loader()).start();
      await DVSceneRuntime(
              document: doc(models: <String>['crate']),
              renderer: DVSceneRecordingRenderer(),
              loader: loader())
          .start();
      expect(posterReports().map((DVLogRecord r) => r.context['asset']),
          <String>['kart', 'crate']);
    });
  });

  group('resource lifetime', () {
    test('dispose releases every upload exactly once, and twice is harmless',
        () async {
      final DVSceneRuntime runtime = DVSceneRuntime(
          document: doc(models: <String>['kart', 'crate']),
          renderer: renderer,
          loader: loader());
      await runtime.start();
      expect(renderer.live, hasLength(2));

      runtime.dispose();
      runtime.dispose();

      expect(renderer.live, isEmpty);
      expect(renderer.releases, hasLength(2));
      expect(renderer.disposed, isTrue);
      expect(runtime.liveResources, 0);
    });

    test('a scene disposed while its assets are still loading leaks nothing',
        () async {
      final DVSceneRuntime runtime =
          DVSceneRuntime(document: doc(), renderer: renderer, loader: loader());
      final Future<DV3DDegradation> starting = runtime.start();
      runtime.dispose();
      await starting;
      expect(renderer.live, isEmpty);
    });

    test('the recording renderer refuses a double release and a use after release',
        () {
      final DVSceneRecordingRenderer r = DVSceneRecordingRenderer();
      final DVSceneResource res = r.upload('kart', model('kart'),
          DVSceneAssetState.debugReady(kart, DVGltf.inspect(kart)));
      r.release(res);
      expect(() => r.release(res), throwsStateError);
      expect(
        () => r.render(DVSceneFrame(
          view: DVSceneView.orbit(distance: 1),
          width: 1,
          height: 1,
          draws: <DVSceneDraw>[
            DVSceneDraw(nodeId: 'n', world: DVMat4.identity(), resource: res),
          ],
        )),
        throwsStateError,
      );
    });

    test('an update keeps the resources it still uses and releases the rest',
        () async {
      final DVSceneRuntime runtime = DVSceneRuntime(
          document: doc(models: <String>['kart', 'crate']),
          renderer: renderer,
          loader: loader());
      await runtime.start();
      final DVSceneResource kept = renderer.live
          .firstWhere((DVSceneResource r) => r.assetKey == 'kart');

      expect(await runtime.update(doc()), DV3DDegradation.none);

      expect(renderer.live, <DVSceneResource>[kept]);
      expect(renderer.uploads, hasLength(2));
      expect(runtime.graph.ids, isNot(contains('crate-a')));
    });
  });
}
