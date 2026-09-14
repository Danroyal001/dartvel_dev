// A model field that holds a 3D asset: what an upload is checked against and
// what the field stores.
//
// An upload that is not a model, is over the size, or draws more triangles
// than the budget must be refused with the reason -- a field that stores it
// anyway renders a blank viewer or stalls a phone, and nobody learns why.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'scene3d_fixtures.dart';

void main() {
  final List<int> kart = glb(kartGltf()); // 19 triangles

  group('the annotation', () {
    test('lives under DVModel and carries the upload limits', () {
      const DVModel field =
          DVModel.model3dField(poster: true, maxSizeMb: 25, maxTriangles: 50000);
      expect(field.isModel3dField, isTrue);
      expect(field.model3dPoster, isTrue);
      expect(field.model3dMaxSizeMb, 25);
      expect(field.model3dMaxTriangles, 50000);
    });

    test('no other DVModel annotation is a 3D field', () {
      expect(const DVModel().isModel3dField, isFalse);
      expect(const DVModel.sensitiveField().isModel3dField, isFalse);
      expect(const DVModel.searchableField().isModel3dField, isFalse);
      expect(const DVModel.featuredImage().isModel3dField, isFalse);
    });
  });

  group('validating an upload', () {
    test('a model within every limit is valid, with what it contains', () {
      final DVModel3DValidation result =
          const DVModel3DFieldPolicy(maxBytes: 1 << 20, maxTriangles: 19)
              .validate(kart);
      expect(result.isValid, isTrue);
      expect(result.summary!.triangles, 19);
      expect(result.problems, isEmpty);
    });

    test('one triangle over the budget is refused, and says by how much', () {
      final DVModel3DValidation result =
          const DVModel3DFieldPolicy(maxTriangles: 18).validate(kart);
      expect(result.isValid, isFalse);
      expect(result.problems.single.kind, DVModel3DProblemKind.triangles);
      expect(result.problems.single.message, contains('19'));
      expect(result.problems.single.message, contains('18'));
    });

    test('an oversized upload is refused before it is parsed', () {
      final DVModel3DValidation result =
          DVModel3DFieldPolicy(maxBytes: kart.length - 1).validate(kart);
      expect(result.problems.single.kind, DVModel3DProblemKind.size);
      expect(result.summary, isNull);
    });

    test('bytes that are not a model are refused as the wrong format', () {
      final DVModel3DValidation result =
          const DVModel3DFieldPolicy().validate(<int>[0x50, 0x4B, 3, 4, 5, 6, 7, 8]);
      expect(result.problems.single.kind, DVModel3DProblemKind.format);
    });

    test('megabytes are mebibytes, as the build and the upload both count', () {
      expect(const DVModel3DFieldPolicy.megabytes(25).maxBytes, 25 * 1024 * 1024);
    });
  });

  group('accepting an upload', () {
    const DVModel3DFieldPolicy policy = DVModel3DFieldPolicy(maxTriangles: 100);

    test('produces the field value, pinned to the exact bytes', () {
      final DVSceneAsset asset =
          policy.accept(kart, storageKey: 'tenants/acme/products/kart.glb');
      expect(asset.kind, DVSceneAssetKind.model);
      expect(asset.source, DVSceneAssetSource.stored);
      expect(asset.reference, 'tenants/acme/products/kart.glb');
      expect(asset.sha256, sha256Hex(kart));
      expect(asset.byteLength, kart.length);
      expect(asset.triangles, 19);
      expect(DVSceneAsset.fromJson(asset.toJson()), asset);
    });

    test('an invalid upload throws with every problem, and produces nothing', () {
      expect(
        () => const DVModel3DFieldPolicy(maxTriangles: 1)
            .accept(kart, storageKey: 'tenants/acme/k.glb'),
        throwsA(isA<DVModel3DRejected>().having(
            (DVModel3DRejected e) => e.validation.problems.single.kind,
            'problem',
            DVModel3DProblemKind.triangles)),
      );
    });

    test('a value accepted for one tenant does not load for another', () {
      final DVSceneAsset asset =
          policy.accept(kart, storageKey: 'tenants/acme/products/kart.glb');
      expect(const DVSceneAssetPolicy().check(asset, tenant: 'acme'), isNull);
      expect(const DVSceneAssetPolicy().check(asset, tenant: 'globex'), isNotNull);
    });
  });
}
