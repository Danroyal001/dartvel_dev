// Where a scene's renderer and asset sources come from, and the headless
// backend a test substitutes for the GPU.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  tearDown(DVScene3D.reset);

  test('with no renderer configured there is none, so a scene is a poster',
      () async {
    expect(DVScene3D.createRenderer(), isNull);
    final DVSceneRuntime runtime = DVSceneRuntime(
      document: DV3DSceneDocument(id: 's'),
      renderer: DVScene3D.createRenderer(),
      loader: DVScene3D.createLoader(),
      enabled: DVScene3D.enabled,
    );
    expect(await runtime.start(), DV3DDegradation.unsupportedTarget);
  });

  test('DV.Test.fake3D() hands every scene its own recording renderer', () {
    final DVSceneFake fake = const DVTestHarness().fake3D();

    final DVSceneRenderer? first = DVScene3D.createRenderer();
    final DVSceneRenderer? second = DVScene3D.createRenderer();

    expect(first, isA<DVSceneRecordingRenderer>());
    expect(identical(first, second), isFalse);
    expect(fake.renderers, <DVSceneRenderer?>[first, second]);
    expect(fake.last, same(second));
  });

  test('a fake can stand in for a GPU that fails to start', () async {
    const DVTestHarness().fake3D(initialization: DV3DDegradation.gpuInitFailed);
    final DVSceneRuntime runtime = DVSceneRuntime(
      document: DV3DSceneDocument(id: 's'),
      renderer: DVScene3D.createRenderer(),
      loader: DVScene3D.createLoader(),
    );
    expect(await runtime.start(), DV3DDegradation.gpuInitFailed);
  });

  test('reset puts back no renderer, the default policy and scene3d enabled',
      () {
    const DVTestHarness().fake3D();
    DVScene3D.configure(
      enabled: false,
      policy: const DVSceneAssetPolicy(allowedHosts: <String>{'cdn.example.com'}),
    );

    DVScene3D.reset();

    expect(DVScene3D.createRenderer(), isNull);
    expect(DVScene3D.enabled, isTrue);
    expect(DVScene3D.policy.allowedHosts, isEmpty);
  });

  test('the configured fetchers and policy reach the loader', () async {
    DVScene3D.configure(
      fetchers: <DVSceneAssetSource, DVSceneAssetFetch>{
        DVSceneAssetSource.bundled: (DVSceneAsset a) async => null,
      },
    );
    final DVSceneAssetState state = await DVScene3D.createLoader().load(
      'k',
      const DVSceneAsset(
        kind: DVSceneAssetKind.texture,
        source: DVSceneAssetSource.bundled,
        reference: 'assets/t.ktx2',
      ),
    );
    expect(state.failure, DVSceneAssetFailure.missing);
  });
}
