// Inspecting a glTF model without a GPU: what an upload is validated against
// and what the scene graph picks by.
//
// A triangle count that skips a child node, or a bounds box that ignores a
// node's transform, passes every budget and picks the wrong place without
// an error; an input with a cycle hangs an import job.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'scene3d_fixtures.dart';

void main() {
  group('a well-formed model', () {
    test('triangles are counted as the default scene draws them', () {
      final DVGltfSummary summary = DVGltf.inspect(glb(kartGltf()));
      // body 36 indices = 12; wheel 9 positions = 3, strip of 6 = 4, lines 0.
      // The unused third mesh is not drawn and not counted.
      expect(summary.triangles, 19);
    });

    test('a mesh used by two nodes is counted twice', () {
      final Map<String, Object?> json = kartGltf();
      (json['nodes']! as List<Object?>).add(<String, Object?>{'name': 'spare', 'mesh': 0});
      ((json['scenes']! as List<Object?>).first! as Map<String, Object?>)['nodes'] =
          <int>[0, 2];
      expect(DVGltf.inspect(glb(json)).triangles, 31);
    });

    test("bounds include every node's transform down the hierarchy", () {
      final DVAabb bounds = DVGltf.inspect(glb(kartGltf())).bounds!;
      expect(bounds.min, const DVVec3(-1, 0, -1));
      expect(bounds.max, const DVVec3(5, 3, 2));
    });

    test('a node given as a matrix is placed by that matrix', () {
      final Map<String, Object?> json = kartGltf();
      final Map<String, Object?> body =
          (json['nodes']! as List<Object?>).first! as Map<String, Object?>;
      body.remove('translation');
      body['matrix'] = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 0, 0, 1];
      final DVAabb bounds = DVGltf.inspect(glb(json)).bounds!;
      expect(bounds.min.x, 9);
    });

    test('names, animations and counts are reported', () {
      final DVGltfSummary summary = DVGltf.inspect(glb(kartGltf()));
      expect(summary.nodeNames, <String>['body', 'wheel']);
      expect(summary.animations, <String>['steamLoop']);
      expect(summary.meshes, 3);
      expect(summary.materials, 1);
      expect(summary.isBinary, isTrue);
    });

    test('a .gltf JSON file is read too', () {
      final DVGltfSummary summary =
          DVGltf.inspect(utf8.encode(jsonEncode(kartGltf())));
      expect(summary.triangles, 19);
      expect(summary.isBinary, isFalse);
    });

    test('a summary survives JSON, so a worker can hand it back', () {
      final DVGltfSummary summary = DVGltf.inspect(glb(kartGltf()));
      final DVGltfSummary back = DVGltfSummary.fromJson(
          jsonDecode(jsonEncode(summary.toJson())) as Map<String, Object?>);
      expect(back.triangles, summary.triangles);
      expect(back.bounds, summary.bounds);
      expect(back.animations, summary.animations);
    });
  });

  group('refusals', () {
    void refused(List<int> bytes, String mentions) => expect(
          () => DVGltf.inspect(bytes),
          throwsA(isA<DVGltfFormatException>().having(
              (DVGltfFormatException e) => e.reason, 'reason', contains(mentions))),
        );

    test('bytes that are not glTF', () {
      refused(utf8.encode('PK not a model'), 'not a glTF');
      refused(const <int>[], 'not a glTF');
    });

    test('a GLB of another version', () {
      refused(glb(kartGltf(), version: 1), 'version');
    });

    test('a GLB whose declared length is not its length', () {
      refused(glb(kartGltf(), declaredLength: 4096), 'length');
    });

    test('a truncated GLB', () {
      final List<int> bytes = glb(kartGltf());
      refused(bytes.sublist(0, bytes.length - 9), 'length');
    });

    test('a node hierarchy with a cycle, rather than hanging', () {
      final Map<String, Object?> json = kartGltf();
      ((json['nodes']! as List<Object?>)[1]! as Map<String, Object?>)['children'] =
          <int>[0];
      refused(glb(json), 'cycle');
    });

    test('a mesh index that does not exist', () {
      final Map<String, Object?> json = kartGltf();
      ((json['nodes']! as List<Object?>)[1]! as Map<String, Object?>)['mesh'] = 9;
      refused(glb(json), 'mesh 9');
    });

    test('a POSITION accessor without bounds', () {
      final Map<String, Object?> json = kartGltf();
      ((json['accessors']! as List<Object?>).first! as Map<String, Object?>)
          .remove('min');
      refused(glb(json), 'min');
    });

    test('an asset version that is not 2.x', () {
      final Map<String, Object?> json = kartGltf()
        ..['asset'] = <String, Object?>{'version': '1.0'};
      refused(glb(json), 'asset.version');
    });
  });
}
