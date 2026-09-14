/// The runtime scene graph: world transforms and picking over a document.
library dartvel.scene3d.graph;

import 'dart:math' as math;

import 'scene_document.dart';
import 'scene_math.dart';

/// A node a ray hit.
final class DVScenePick {
  const DVScenePick(this.nodeId, this.distance, this.point);

  final String nodeId;

  /// World-space distance from the ray origin, in metres.
  final double distance;

  /// The world-space point hit.
  final DVVec3 point;

  @override
  String toString() => 'DVScenePick($nodeId at $distance)';
}

final class _Node {
  _Node(this.data, this.parent);

  final DVSceneNodeData data;
  final int parent;

  /// One past the last descendant: this node's subtree is `[index, end)`,
  /// because nodes are stored depth first.
  int end = 0;
  late DVTransform local = data.transform;
  late bool visible = data.visible;
  DVAabb? assetBounds;
  DVMat4? world;
}

/// A scene graph built from a [DV3DSceneDocument].
///
/// Node order is the document's, depth first, and never changes: traversal,
/// draw lists and pick tie-breaks all follow it, so the same document
/// produces the same frame and the same answers on every run.
///
/// World matrices are computed on read and cached; changing a node's
/// transform invalidates its whole subtree at once, so a hit test after a
/// move can never read a matrix from before it.
final class DVSceneGraph {
  DVSceneGraph(DV3DSceneDocument document)
      : _document = document,
        basis = _basisFor(document) {
    void add(DVSceneNodeData data, int parent) {
      final int index = _nodes.length;
      _nodes.add(_Node(data, parent));
      _index[data.id] = index;
      for (final DVSceneNodeData child in data.children) {
        add(child, index);
      }
      _nodes[index].end = _nodes.length;
    }

    for (final DVSceneNodeData root in document.nodes) {
      add(root, -1);
    }
  }

  final DV3DSceneDocument _document;
  final List<_Node> _nodes = <_Node>[];
  final Map<String, int> _index = <String, int>{};

  /// The conversion from the document's units, up axis and handedness into
  /// world space (right-handed, Y up, metres), applied above every root.
  final DVMat4 basis;

  /// Whether [basis] mirrors, which flips triangle winding: a renderer must
  /// cull the other face or the model renders inside out.
  bool get basisMirrors => basis.determinant3 < 0;

  static DVMat4 _basisFor(DV3DSceneDocument document) {
    final double u = document.units.metersPerUnit;
    final bool zUp = document.upAxis == DVSceneUpAxis.z;
    // A left-handed document mirrors its forward axis: the one that is
    // neither X nor up.
    final bool left = document.handedness == DVSceneHandedness.left;
    final DVVec3 mirror = DVVec3(
      1,
      left && zUp ? -1 : 1,
      left && !zUp ? -1 : 1,
    );
    final DVMat4 scale = DVMat4.scaling(mirror * u);
    if (!zUp) return scale;
    // Z up to Y up: -90 degrees about X, taking (x, y, z) to (x, z, -y).
    return DVMat4.compose(
          DVVec3.zero,
          DVQuat.axisAngle(const DVVec3(1, 0, 0), -math.pi / 2),
          DVVec3.one,
        ) *
        scale;
  }

  /// Every node id, depth first in document order.
  List<String> get ids =>
      <String>[for (final _Node n in _nodes) n.data.id];

  bool contains(String id) => _index.containsKey(id);

  int _at(String id) {
    final int? index = _index[id];
    if (index == null) {
      throw ArgumentError.value(id, 'id', 'no node with this id in the scene');
    }
    return index;
  }

  DVSceneNodeData data(String id) => _nodes[_at(id)].data;

  String? parentOf(String id) {
    final int parent = _nodes[_at(id)].parent;
    return parent < 0 ? null : _nodes[parent].data.id;
  }

  DVTransform transformOf(String id) => _nodes[_at(id)].local;

  void setTransform(String id, DVTransform transform) {
    final int index = _at(id);
    final _Node node = _nodes[index];
    if (node.local == transform) return;
    node.local = transform;
    for (int i = index; i < node.end; i++) {
      _nodes[i].world = null;
    }
  }

  bool visibleOf(String id) => _nodes[_at(id)].visible;

  void setVisible(String id, bool visible) {
    _nodes[_at(id)].visible = visible;
  }

  /// Whether this node and every ancestor are visible.
  bool isVisibleInWorld(String id) {
    for (int i = _at(id); i >= 0; i = _nodes[i].parent) {
      if (!_nodes[i].visible) return false;
    }
    return true;
  }

  /// Records the local bounds a loaded asset reported for a model node, or
  /// clears them with null when the asset is unloaded.
  void setLocalBounds(String id, DVAabb? bounds) {
    _nodes[_at(id)].assetBounds = bounds;
  }

  /// The local-space bounds picking and culling use: the primitive's for a
  /// mesh, the asset's for a model once known, otherwise null.
  DVAabb? localBounds(String id) {
    final _Node node = _nodes[_at(id)];
    return node.data.primitive?.localBounds ?? node.assetBounds;
  }

  DVMat4 worldMatrix(String id) => _world(_at(id));

  DVMat4 _world(int index) {
    final _Node node = _nodes[index];
    return node.world ??= (node.parent < 0 ? basis : _world(node.parent)) *
        node.local.matrix;
  }

  DVVec3 worldPosition(String id) => worldMatrix(id).translation;

  /// The world-space box around a node's own shape, or null when it has none.
  DVAabb? worldBounds(String id) =>
      localBounds(id)?.transformed(worldMatrix(id));

  /// The nearest visible node [ray] hits, or null.
  ///
  /// Each node is tested in its own local space against its true shape --
  /// an exact box, an exact ellipsoid for a scaled sphere, the asset's box for
  /// a model -- rather than against a world-aligned box, which would report a
  /// hit in the empty corner of anything rotated. Exact ties go to the earlier
  /// node in document order. [where] narrows the candidates, e.g. to nodes
  /// with a tap handler.
  DVScenePick? pick(DVRay ray, {bool Function(String id)? where}) {
    DVScenePick? best;
    final double directionLength = ray.direction.length;
    if (directionLength == 0) return null;
    for (int i = 0; i < _nodes.length; i++) {
      final _Node node = _nodes[i];
      final String id = node.data.id;
      final DVAabb? bounds = node.data.primitive?.localBounds ?? node.assetBounds;
      if (bounds == null) continue;
      if (where != null && !where(id)) continue;
      if (!isVisibleInWorld(id)) continue;
      final DVMat4 world = _world(i);
      final DVMat4? inverse = world.inverse();
      if (inverse == null) continue;
      final DVRay local = DVRay(
        inverse.transformPoint(ray.origin),
        inverse.transformDirection(ray.direction),
      );
      final double? t = node.data.primitive?.shape == DVScenePrimitiveShape.sphere
          ? _sphere(local, node.data.primitive!.radius)
          : bounds.intersect(local);
      if (t == null) continue;
      // The map from world to local is affine, so the ray parameter is the
      // same in both spaces; only the length of a unit of it differs.
      final double distance = t * directionLength;
      if (best == null || distance < best.distance) {
        best = DVScenePick(id, distance, ray.pointAt(t));
      }
    }
    return best;
  }

  static double? _sphere(DVRay ray, double radius) {
    final DVVec3 o = ray.origin;
    final DVVec3 d = ray.direction;
    final double a = d.dot(d);
    final double b = 2 * o.dot(d);
    final double c = o.dot(o) - radius * radius;
    final double disc = b * b - 4 * a * c;
    if (disc < 0) return null;
    final double root = math.sqrt(disc);
    final double t0 = (-b - root) / (2 * a);
    final double t1 = (-b + root) / (2 * a);
    if (t1 < 0) return null;
    return t0 < 0 ? 0 : t0;
  }

  /// The document with every node's current transform and visibility, for
  /// saving an edit made through the graph. Everything else -- ids, order,
  /// assets, keys this version does not know -- is the original's.
  DV3DSceneDocument toDocument() {
    DVSceneNodeData rebuild(DVSceneNodeData data) {
      final _Node node = _nodes[_index[data.id]!];
      return data.copyWith(
        transform: node.local,
        visible: node.visible,
        children: <DVSceneNodeData>[
          for (final DVSceneNodeData child in data.children) rebuild(child),
        ],
      );
    }

    return DV3DSceneDocument(
      id: _document.id,
      units: _document.units,
      upAxis: _document.upAxis,
      handedness: _document.handedness,
      environment: _document.environment,
      poster: _document.poster,
      assets: _document.assets,
      nodes: <DVSceneNodeData>[
        for (final DVSceneNodeData root in _document.nodes) rebuild(root),
      ],
      extra: _document.extra,
    );
  }
}
