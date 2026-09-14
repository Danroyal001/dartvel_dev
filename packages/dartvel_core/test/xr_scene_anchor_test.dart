// Anchors on scene nodes: typed data in the document, and a placement in the
// graph.
//
// An anchor pins a node to the world, so the node's parent chain stops
// applying to it; its own transform and its children still do. What must
// never happen silently: a node drawn at the origin while its anchor is still
// being looked for (it pops into place a second later), a node that lost
// tracking drawn where it was last seen (it drifts), or a mirrored frame
// accepted as a placement (it renders inside out).
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
  DVSceneHandedness handedness = DVSceneHandedness.right,
  DVAnchor anchor = const DVAnchor.plane(DVPlane.vertical),
}) =>
    DV3DSceneDocument(
      id: 'anchored',
      units: units,
      handedness: handedness,
      nodes: <DVSceneNodeData>[
        DVSceneNodeData.group(
          id: 'room',
          transform: DVTransform(translation: const DVVec3(10, 0, 0)),
          children: <DVSceneNodeData>[
            DVSceneNodeData(
              id: 'tag',
              kind: DVSceneNodeKind.mesh,
              primitive: const DVScenePrimitive.box(DVVec3(1, 1, 1)),
              transform: DVTransform(translation: const DVVec3(0, 0.5, 0)),
              anchor: anchor,
              children: <DVSceneNodeData>[
                DVSceneNodeData.mesh(
                  id: 'label',
                  primitive: const DVScenePrimitive.box(DVVec3(0.2, 0.2, 0.2)),
                  transform: DVTransform(translation: const DVVec3(0, 1, 0)),
                ),
              ],
            ),
          ],
        ),
      ],
    );

void main() {
  group('in the document', () {
    test('every anchor type round-trips exactly', () {
      for (final DVAnchor anchor in <DVAnchor>[
        const DVAnchor.plane(DVPlane.vertical),
        const DVAnchor.plane(DVPlane.horizontal),
        const DVAnchor.image('counterTag'),
        const DVAnchor.hand(DVHand.left),
        const DVAnchor.world(id: 'lobby-sign'),
      ]) {
        final DV3DSceneDocument doc = _doc(anchor: anchor);
        final DV3DSceneDocument back = DV3DSceneDocument.decode(doc.encode());
        expect(back.find('tag')!.anchor, anchor);
        expect(back.encode(), doc.encode());
      }
    });

    test('an unanchored node writes no anchor key', () {
      expect(_doc().find('label')!.toJson().containsKey('anchor'), isFalse);
    });

    test('a malformed anchor is refused with the path to it', () {
      final Map<String, Object?> json = _doc().toJson();
      Map<String, Object?> tag() =>
          ((json['nodes']! as List<Object?>)[0]! as Map<String, Object?>)['children']
              .let((Object? c) => (c! as List<Object?>)[0]! as Map<String, Object?>);

      tag()['anchor'] = <String, Object?>{'type': 'gaze'};
      expect(
        () => DV3DSceneDocument.fromJson(json),
        throwsA(isA<DV3DSceneFormatException>()
            .having((DV3DSceneFormatException e) => e.path, 'path',
                'nodes[0].children[0].anchor.type')),
      );

      tag()['anchor'] = <String, Object?>{'type': 'world', 'id': ''};
      expect(
        () => DV3DSceneDocument.fromJson(json),
        throwsA(isA<DV3DSceneFormatException>()
            .having((DV3DSceneFormatException e) => e.path, 'path',
                'nodes[0].children[0].anchor.id')),
      );
    });
  });

  group('in the graph', () {
    test('an anchor nothing has placed sits at the scene origin, parent ignored', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      expect(graph.anchorPlacementOf('tag'), DVSceneAnchorPlacement.origin);
      expect(graph.worldPosition('tag'), _near(const DVVec3(0, 0.5, 0)));
      expect(graph.worldPosition('label'), _near(const DVVec3(0, 1.5, 0)));
    });

    test('a placed anchor carries the node and its children, and picking follows', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      final DVMat4 frame = DVMat4.compose(
        const DVVec3(2, 0, -3),
        DVQuat.axisAngle(DVVec3.up, math.pi / 2),
        DVVec3.one,
      );
      graph.placeAnchor('tag', frame);

      expect(graph.anchorPlacementOf('tag'), DVSceneAnchorPlacement.located);
      expect(graph.worldPosition('tag'), _near(const DVVec3(2, 0.5, -3)));
      expect(graph.worldPosition('label'), _near(const DVVec3(2, 1.5, -3)));

      final DVScenePick? hit = graph.pick(
          const DVRay(DVVec3(2, 0.5, 5), DVVec3(0, 0, -1)));
      expect(hit?.nodeId, 'tag');
      expect(
          graph.pick(const DVRay(DVVec3(0, 0.5, 5), DVVec3(0, 0, -1))), isNull,
          reason: 'nothing is left at the origin once the anchor is placed');
    });

    test('moving the frame invalidates the subtree', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      graph.placeAnchor('tag', DVMat4.translation(const DVVec3(1, 0, 0)));
      expect(graph.worldPosition('label'), _near(const DVVec3(1, 1.5, 0)));
      graph.placeAnchor('tag', DVMat4.translation(const DVVec3(-4, 0, 0)));
      expect(graph.worldPosition('label'), _near(const DVVec3(-4, 1.5, 0)));
    });

    test('a hidden anchor is neither drawn nor picked, and neither are its children', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      graph.hideAnchor('tag');
      expect(graph.isVisibleInWorld('tag'), isFalse);
      expect(graph.isVisibleInWorld('label'), isFalse);
      expect(
          graph.pick(const DVRay(DVVec3(0, 0.5, 5), DVVec3(0, 0, -1))), isNull);
    });

    test('the document basis still applies beneath the anchor frame', () {
      final DVSceneGraph graph =
          DVSceneGraph(_doc(units: DVSceneUnits.centimeters));
      graph.placeAnchor('tag', DVMat4.translation(const DVVec3(1, 0, 0)));
      // 0.5 cm up, in a document whose unit is the centimetre.
      expect(graph.worldPosition('tag'), _near(const DVVec3(1, 0.005, 0)));
    });

    test('a mirrored frame is refused rather than rendered inside out', () {
      final DVSceneGraph graph = DVSceneGraph(_doc());
      expect(
        () => graph.placeAnchor('tag', DVMat4.scaling(const DVVec3(1, 1, -1))),
        throwsArgumentError,
      );
      expect(
        () => graph.placeAnchor('room', DVMat4.identity()),
        throwsArgumentError,
        reason: 'room has no anchor to place',
      );
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
