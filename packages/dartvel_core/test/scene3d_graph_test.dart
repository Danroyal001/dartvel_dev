// The scene graph: world transforms, basis conversion and picking.
//
// Picking is where a stale transform hides: a hit test that reads a cached
// world matrix after a parent moved answers with a node that is no longer
// under the pointer, and nothing throws.
import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const double _eps = 1e-9;

Matcher _near(DVVec3 v, [double eps = _eps]) => predicate<DVVec3>(
      (DVVec3 a) =>
          (a.x - v.x).abs() < eps &&
          (a.y - v.y).abs() < eps &&
          (a.z - v.z).abs() < eps,
      'within $eps of $v',
    );

DV3DSceneDocument _doc({
  DVSceneUnits units = DVSceneUnits.meters,
  DVSceneUpAxis up = DVSceneUpAxis.y,
  DVSceneHandedness handedness = DVSceneHandedness.right,
  List<DVSceneNodeData>? nodes,
}) =>
    DV3DSceneDocument(
      id: 'test',
      units: units,
      upAxis: up,
      handedness: handedness,
      nodes: nodes ??
          <DVSceneNodeData>[
            DVSceneNodeData.group(
              id: 'parent',
              transform: DVTransform(translation: const DVVec3(10, 0, 0)),
              children: <DVSceneNodeData>[
                DVSceneNodeData.mesh(
                  id: 'box',
                  primitive: const DVScenePrimitive.box(DVVec3(1, 1, 1)),
                  transform: DVTransform(translation: const DVVec3(0, 0, -5)),
                ),
              ],
            ),
          ],
    );

void main() {
  group('math', () {
    test('a quaternion rotation about Y turns +X toward -Z (right-handed)', () {
      final DVQuat q = DVQuat.axisAngle(const DVVec3(0, 1, 0), math.pi / 2);
      expect(q.rotate(const DVVec3(1, 0, 0)), _near(const DVVec3(0, 0, -1)));
    });

    test('a matrix times its inverse is the identity', () {
      final DVMat4 m = DVTransform(
        translation: const DVVec3(1, -2, 3),
        rotation: DVQuat.axisAngle(const DVVec3(1, 1, 0).normalized(), 1.1),
        scale: const DVVec3(2, 0.5, 3),
      ).matrix;
      final DVMat4 product = m * m.inverse()!;
      for (int i = 0; i < 16; i++) {
        expect(product.storage[i], closeTo(DVMat4.identity().storage[i], 1e-12),
            reason: 'element $i');
      }
    });

    test('a singular matrix has no inverse rather than a garbage one', () {
      expect(DVMat4.scaling(const DVVec3(1, 0, 1)).inverse(), isNull);
    });
  });

  group('world transforms', () {
    test("a child's world position composes its parent's", () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      expect(graph.worldPosition('box'), _near(const DVVec3(10, 0, -5)));
    });

    test('moving a parent moves its child on the next read', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      expect(graph.worldPosition('box'), _near(const DVVec3(10, 0, -5)));

      graph.setTransform(
          'parent', DVTransform(translation: const DVVec3(-3, 2, 0)));

      expect(graph.worldPosition('box'), _near(const DVVec3(-3, 2, -5)));
    });

    test('a document in centimetres is scaled to metres in world space', () {
      final DVSceneGraph graph = DVSceneGraph(_doc(units: DVSceneUnits.centimeters));
      expect(graph.worldPosition('box'), _near(const DVVec3(0.1, 0, -0.05)));
    });

    test('a Z-up document stands up in the Y-up world', () {
      final DVSceneGraph graph = DVSceneGraph(_doc(
        up: DVSceneUpAxis.z,
        nodes: <DVSceneNodeData>[
          DVSceneNodeData.group(
              id: 'top',
              transform: DVTransform(translation: const DVVec3(0, 0, 2))),
          DVSceneNodeData.group(
              id: 'ahead',
              transform: DVTransform(translation: const DVVec3(0, 3, 0))),
        ],
      ));
      // Up stays up.
      expect(graph.worldPosition('top'), _near(const DVVec3(0, 2, 0)));
      // Right-handed Z-up +Y maps to right-handed Y-up -Z.
      expect(graph.worldPosition('ahead'), _near(const DVVec3(0, 0, -3)));
    });

    test('a left-handed document is mirrored, and says that it is', () {
      final DVSceneGraph left = DVSceneGraph(_doc(
        handedness: DVSceneHandedness.left,
        nodes: <DVSceneNodeData>[
          DVSceneNodeData.group(
              id: 'p', transform: DVTransform(translation: const DVVec3(1, 2, 3))),
        ],
      ));
      expect(left.worldPosition('p'), _near(const DVVec3(1, 2, -3)));
      expect(left.basisMirrors, isTrue);
      expect(DVSceneGraph(_doc()).basisMirrors, isFalse);
    });
  });

  group('order and ids', () {
    test('traversal is document order, depth first, every time', () {
      final DVSceneGraph graph = DVSceneGraph(DV3DSceneDocument(
        id: 'o',
        nodes: <DVSceneNodeData>[
          DVSceneNodeData.group(id: 'z', children: <DVSceneNodeData>[
            DVSceneNodeData.group(id: 'b'),
            DVSceneNodeData.group(id: 'a'),
          ]),
          DVSceneNodeData.group(id: 'm'),
        ],
      ));
      expect(graph.ids, <String>['z', 'b', 'a', 'm']);
      expect(graph.parentOf('a'), 'z');
      expect(graph.parentOf('m'), isNull);
    });

    test('an unknown id is an error, not a silent no-op', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      expect(() => graph.setTransform('nope', DVTransform()),
          throwsA(isA<ArgumentError>()));
    });
  });

  group('picking', () {
    DVRay forward(double x, double y) =>
        DVRay(DVVec3(x, y, 0), const DVVec3(0, 0, -1));

    test('a ray through the box hits it at the near face', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      final DVScenePick? hit = graph.pick(forward(10, 0));
      expect(hit?.nodeId, 'box');
      expect(hit!.distance, closeTo(4.5, 1e-9));
      expect(hit.point, _near(const DVVec3(10, 0, -4.5)));
    });

    test('after the parent moves, the old place is empty and the new one hits',
        () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      expect(graph.pick(forward(10, 0))?.nodeId, 'box');

      graph.setTransform('parent', DVTransform(translation: const DVVec3(0, 5, 0)));

      expect(graph.pick(forward(10, 0)), isNull);
      expect(graph.pick(forward(0, 5))?.nodeId, 'box');
    });

    test('a rotated box is hit by its true shape, not its world bounds', () {
      // A unit box turned 45 degrees about Z has a world AABB reaching
      // x = 0.707; its corner along the diagonal is empty space.
      final DVSceneGraph graph = DVSceneGraph(_doc(nodes: <DVSceneNodeData>[
        DVSceneNodeData.mesh(
          id: 'turned',
          primitive: const DVScenePrimitive.box(DVVec3(1, 1, 1)),
          transform: DVTransform(
            translation: const DVVec3(0, 0, -5),
            rotation: DVQuat.axisAngle(const DVVec3(0, 0, 1), math.pi / 4),
          ),
        ),
      ]));
      expect(graph.pick(forward(0.6, 0.6)), isNull);
      expect(graph.pick(forward(0.6, 0))?.nodeId, 'turned');
    });

    test('the nearest of two overlapping nodes wins', () {
      final DVSceneGraph graph = DVSceneGraph(_doc(nodes: <DVSceneNodeData>[
        DVSceneNodeData.mesh(
          id: 'far',
          primitive: DVScenePrimitive.sphere(1),
          transform: DVTransform(translation: const DVVec3(0, 0, -10)),
        ),
        DVSceneNodeData.mesh(
          id: 'near',
          primitive: DVScenePrimitive.sphere(1),
          transform: DVTransform(translation: const DVVec3(0, 0, -4)),
        ),
      ]));
      final DVScenePick? hit = graph.pick(forward(0, 0));
      expect(hit?.nodeId, 'near');
      expect(hit!.distance, closeTo(3, 1e-9));
    });

    test('an exact tie goes to the earlier node in document order', () {
      List<DVSceneNodeData> twins(List<String> ids) => <DVSceneNodeData>[
            for (final String id in ids)
              DVSceneNodeData.mesh(
                id: id,
                primitive: const DVScenePrimitive.box(DVVec3(1, 1, 1)),
                transform: DVTransform(translation: const DVVec3(0, 0, -5)),
              ),
          ];
      expect(DVSceneGraph(_doc(nodes: twins(<String>['a', 'b'])))
          .pick(forward(0, 0))?.nodeId, 'a');
      expect(DVSceneGraph(_doc(nodes: twins(<String>['b', 'a'])))
          .pick(forward(0, 0))?.nodeId, 'b');
    });

    test('a hidden node, or a node under a hidden parent, is not picked', () {
      final DV3DSceneDocument doc = _doc();
      final DVSceneGraph graph = DVSceneGraph(doc);
      graph.setVisible('parent', false);
      expect(graph.pick(forward(10, 0)), isNull);
      graph.setVisible('parent', true);
      expect(graph.pick(forward(10, 0))?.nodeId, 'box');
    });

    test('a non-uniformly scaled sphere is picked as the ellipsoid it is', () {
      final DVSceneGraph graph = DVSceneGraph(_doc(nodes: <DVSceneNodeData>[
        DVSceneNodeData.mesh(
          id: 'egg',
          primitive: DVScenePrimitive.sphere(1),
          transform: DVTransform(
            translation: const DVVec3(0, 0, -10),
            scale: const DVVec3(3, 1, 1),
          ),
        ),
      ]));
      expect(graph.pick(forward(2.5, 0))?.nodeId, 'egg');
      expect(graph.pick(forward(0, 1.5)), isNull);
    });

    test('a model is picked by the bounds its asset reported', () {
      final DVSceneGraph graph = DVSceneGraph(DV3DSceneDocument(
        id: 'm',
        assets: const <String, DVSceneAsset>{
          'kart': DVSceneAsset(
              kind: DVSceneAssetKind.model,
              source: DVSceneAssetSource.bundled,
              reference: 'assets/models/kart.glb'),
        },
        nodes: <DVSceneNodeData>[
          DVSceneNodeData.model(
            id: 'kart-1',
            asset: 'kart',
            transform: DVTransform(translation: const DVVec3(0, 0, -5)),
          ),
        ],
      ));
      // Nothing is known about its shape until the asset has loaded.
      expect(graph.pick(forward(0, 0)), isNull);

      graph.setLocalBounds('kart-1',
          const DVAabb(DVVec3(-1, -1, -1), DVVec3(1, 1, 1)));
      expect(graph.pick(forward(0, 0))?.nodeId, 'kart-1');
    });

    test('a scene in centimetres reports hit distances in metres', () {
      final DVSceneGraph graph = DVSceneGraph(_doc(units: DVSceneUnits.centimeters));
      final DVScenePick? hit = graph.pick(forward(0.1, 0));
      expect(hit?.nodeId, 'box');
      expect(hit!.distance, closeTo(0.045, 1e-12));
    });
  });
}
