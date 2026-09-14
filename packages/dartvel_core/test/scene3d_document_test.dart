// Scene documents: what a Studio edit, an OTA bundle and the running
// application all read.
//
// The failures that matter here are the quiet ones. A transform that loses a
// digit, a unit or a handedness that is dropped on the way through, a node id
// that is regenerated, a child order that is reshuffled -- each of those
// produces a scene that still renders, just not the one that was saved.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DV3DSceneDocument _sample() => DV3DSceneDocument(
      id: 'showroom',
      units: DVSceneUnits.centimeters,
      upAxis: DVSceneUpAxis.z,
      handedness: DVSceneHandedness.left,
      environment: 'studio',
      assets: <String, DVSceneAsset>{
        'kart': const DVSceneAsset(
          kind: DVSceneAssetKind.model,
          source: DVSceneAssetSource.stored,
          reference: 'tenants/acme/models/kart.glb',
          sha256:
              '0b2d3f7f4f2b5e0d0f5a3d1f9c9a7e7c6b1a2d3e4f5a6b7c8d9e0f1a2b3c4d5e',
          byteLength: 1024,
        ),
      },
      nodes: <DVSceneNodeData>[
        DVSceneNodeData.group(
          id: 'root',
          transform: DVTransform(
            translation: const DVVec3(0.1, 0.2, 0.30000000000000004),
            rotation: DVQuat.axisAngle(const DVVec3(0, 1, 0), 0.7),
            scale: const DVVec3(1, 2, 3),
          ),
          children: <DVSceneNodeData>[
            DVSceneNodeData.model(id: 'kart-1', asset: 'kart'),
            DVSceneNodeData.mesh(
              id: 'floor',
              primitive: const DVScenePrimitive.box(DVVec3(10, 0.1, 10)),
              visible: false,
            ),
            DVSceneNodeData.light(
              id: 'sun',
              light: const DVSceneLight.directional(
                direction: DVVec3(-1, -2, -1),
                intensity: 3.5,
                castShadows: true,
              ),
            ),
          ],
        ),
        DVSceneNodeData.camera(
          id: 'cam',
          camera: const DVSceneCameraData.perspective(
            fovYDegrees: 45,
            near: 0.05,
            far: 500,
          ),
          transform: DVTransform(translation: const DVVec3(0, 1.6, 4)),
        ),
      ],
    );

void main() {
  group('round trip', () {
    test('encoding then decoding gives back an identical document', () {
      final DV3DSceneDocument original = _sample();
      final String encoded = original.encode();
      final DV3DSceneDocument decoded = DV3DSceneDocument.decode(encoded);

      expect(decoded.encode(), encoded);
      expect(decoded.units, DVSceneUnits.centimeters);
      expect(decoded.upAxis, DVSceneUpAxis.z);
      expect(decoded.handedness, DVSceneHandedness.left);
      expect(decoded.environment, 'studio');
    });

    test('transform components survive to the last bit', () {
      final DV3DSceneDocument decoded =
          DV3DSceneDocument.decode(_sample().encode());
      final DVTransform before = _sample().nodes.first.transform;
      final DVTransform after = decoded.nodes.first.transform;

      expect(after.translation.z, 0.30000000000000004);
      expect(after.translation, before.translation);
      expect(after.rotation, before.rotation);
      expect(after.scale, before.scale);
    });

    test('node ids and child order are kept exactly', () {
      final DV3DSceneDocument decoded =
          DV3DSceneDocument.decode(_sample().encode());

      expect(decoded.nodeIds(), <String>['root', 'kart-1', 'floor', 'sun', 'cam']);
      expect(decoded.nodes.first.children.map((DVSceneNodeData n) => n.id),
          <String>['kart-1', 'floor', 'sun']);
    });

    test('node kinds and their typed payloads come back', () {
      final DV3DSceneDocument decoded =
          DV3DSceneDocument.decode(_sample().encode());
      final DVSceneNodeData floor = decoded.find('floor')!;
      final DVSceneNodeData sun = decoded.find('sun')!;
      final DVSceneNodeData cam = decoded.find('cam')!;

      expect(floor.kind, DVSceneNodeKind.mesh);
      expect(floor.visible, isFalse);
      expect(floor.primitive!.size, const DVVec3(10, 0.1, 10));
      expect(sun.light!.castShadows, isTrue);
      expect(sun.light!.intensity, 3.5);
      expect(cam.camera!.fovYDegrees, 45);
      expect(decoded.find('kart-1')!.asset, 'kart');
      expect(decoded.assets['kart']!.sha256, _sample().assets['kart']!.sha256);
    });

    test('a key written by a newer version survives a round trip', () {
      // A document outlives the version that wrote it. Dropping what this
      // version does not understand and writing the rest back would delete
      // the newer version's data on the first save.
      final Map<String, Object?> json = _sample().toJson();
      ((json['nodes']! as List<Object?>).first! as Map<String, Object?>)['lod'] =
          <String, Object?>{'levels': 3};
      json['physics'] = 'rapier';

      final DV3DSceneDocument decoded =
          DV3DSceneDocument.fromJson(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
      final Map<String, Object?> again = decoded.toJson();

      expect(again['physics'], 'rapier');
      expect(
        ((again['nodes']! as List<Object?>).first! as Map<String, Object?>)['lod'],
        <String, Object?>{'levels': 3},
      );
    });

    test('keys a newer version wrote encode in one order however they arrived',
        () {
      // A content version is stored as canonical JSON with its keys sorted, so
      // a document read back from the workflow meets its extra keys in a
      // different order from the one it was written in.
      DV3DSceneDocument withExtra(Map<String, Object?> extra) =>
          DV3DSceneDocument(
            id: 'e',
            extra: extra,
            nodes: <DVSceneNodeData>[
              DVSceneNodeData(
                id: 'n',
                kind: DVSceneNodeKind.group,
                extra: extra,
              ),
            ],
          );

      expect(
        withExtra(<String, Object?>{
          'zeta': 1,
          'alpha': <String, Object?>{'y': 2, 'b': 3},
        }).encode(),
        withExtra(<String, Object?>{
          'alpha': <String, Object?>{'b': 3, 'y': 2},
          'zeta': 1,
        }).encode(),
      );
    });

    test('encoding is byte-identical however the assets were inserted', () {
      DV3DSceneDocument withAssets(List<String> order) => DV3DSceneDocument(
            id: 'a',
            assets: <String, DVSceneAsset>{
              for (final String key in order)
                key: DVSceneAsset(
                  kind: DVSceneAssetKind.model,
                  source: DVSceneAssetSource.bundled,
                  reference: 'assets/models/$key.glb',
                ),
            },
            nodes: const <DVSceneNodeData>[],
          );

      expect(withAssets(<String>['b', 'a', 'c']).encode(),
          withAssets(<String>['c', 'b', 'a']).encode());
    });
  });

  group('refusals', () {
    Map<String, Object?> json() => _sample().toJson();

    void expectRefused(Map<String, Object?> value, String mentions) {
      expect(
        () => DV3DSceneDocument.fromJson(
            jsonDecode(jsonEncode(value)) as Map<String, Object?>),
        throwsA(isA<DV3DSceneFormatException>().having(
            (DV3DSceneFormatException e) => e.toString(), 'message', contains(mentions))),
      );
    }

    test('two nodes with one id are refused, not merged', () {
      final Map<String, Object?> value = json();
      final List<Object?> nodes = value['nodes']! as List<Object?>;
      (nodes.last! as Map<String, Object?>)['id'] = 'sun';
      expectRefused(value, "'sun'");
    });

    test('a node naming an asset the document does not declare is refused', () {
      final Map<String, Object?> value = json();
      value['assets'] = <String, Object?>{};
      expectRefused(value, "'kart'");
    });

    test('a format version this runtime does not know is refused', () {
      final Map<String, Object?> value = json()..['format'] = 99;
      expectRefused(value, 'format');
    });

    test('a non-finite transform component is refused with its path', () {
      final Map<String, Object?> value = json();
      final Map<String, Object?> root =
          (value['nodes']! as List<Object?>).first! as Map<String, Object?>;
      (root['transform']! as Map<String, Object?>)['t'] = <Object?>[0, 'NaN', 0];
      expectRefused(value, 'nodes[0].transform.t');
    });

    test('a units name that is not known is refused rather than read as metres',
        () {
      expectRefused(json()..['units'] = 'furlongs', 'units');
    });

    test('a scale of zero is refused, because nothing can be picked through it',
        () {
      final Map<String, Object?> value = json();
      final Map<String, Object?> root =
          (value['nodes']! as List<Object?>).first! as Map<String, Object?>;
      (root['transform']! as Map<String, Object?>)['s'] = <Object?>[1, 0, 1];
      expectRefused(value, 'nodes[0].transform.s');
    });

    test('an empty or malformed node id is refused', () {
      final Map<String, Object?> value = json();
      ((value['nodes']! as List<Object?>).last! as Map<String, Object?>)['id'] =
          'has space';
      expectRefused(value, 'id');
    });
  });
}
