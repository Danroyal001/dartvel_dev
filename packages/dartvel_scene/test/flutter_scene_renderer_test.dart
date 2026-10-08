import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_scene/dartvel_scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DVScene3D.reset);

  test('install makes every new scene get a Flutter Scene renderer', () {
    expect(DVScene3D.createRenderer(), isNull);
    DVFlutterScene.install();
    final DVSceneRenderer? renderer = DVScene3D.createRenderer();
    expect(renderer, isA<DVFlutterSceneRenderer>());
    expect(renderer!.name, 'flutter_scene');
    // Each scene owns its renderer, so two scenes never share one.
    expect(identical(renderer, DVScene3D.createRenderer()), isFalse);
  });

  test('without Flutter GPU, initialize reports gpuInitFailed instead of throwing', () async {
    // flutter_test runs on no GPU at all: the honest answer is the poster.
    final DVFlutterSceneRenderer renderer = DVFlutterSceneRenderer();
    expect(await renderer.initialize(), DV3DDegradation.gpuInitFailed);
    expect(renderer.initializationError, isNotNull);
    renderer.dispose();
  });

  test('a material asset that does not parse is refused at upload, naming the asset', () async {
    final DVFlutterSceneRenderer renderer = DVFlutterSceneRenderer();
    const DVSceneAsset material =
        DVSceneAsset(kind: .material, source: .bundled, reference: 'assets/materials/grass.json');
    expect(
      () => renderer.upload('grass', material, DVSceneAssetState.debugReady('{"colour": 1}'.codeUnits)),
      throwsA(isA<DVSceneMaterialFormatException>()),
    );
    renderer.dispose();
  });

  test('releasing a resource twice, or after dispose, is harmless', () {
    final DVFlutterSceneRenderer renderer = DVFlutterSceneRenderer();
    const DVSceneAsset material =
        DVSceneAsset(kind: .material, source: .bundled, reference: 'assets/materials/grass.json');
    final DVSceneResource resource =
        renderer.upload('grass', material, DVSceneAssetState.debugReady('{"baseColor": "#2E8B57"}'.codeUnits));
    expect(renderer.liveResources, 1);
    renderer.release(resource);
    renderer.release(resource);
    expect(renderer.liveResources, 0);
    renderer.dispose();
    renderer.release(resource);
  });
}
