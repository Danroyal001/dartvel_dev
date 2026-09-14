/// Anchors: typed data on a scene node saying what in the real world it is
/// pinned to.
///
/// Data only. Whether a target can honour an anchor is the XR runtime's
/// question (`DVSpatialCapability.anchors`), and where the anchor is found is
/// the graph's placement, set by that runtime. A document carries anchors
/// whatever it is rendered on, so a scene written for a headset still opens
/// in Studio and on a phone.
library dartvel.scene3d.anchor;

import 'dart:convert';

import 'scene_document.dart' show DV3DSceneFormatException;

/// The kinds of anchor, as a closed set.
enum DVAnchorType { plane, image, hand, world, shared }

/// Which detected planes a plane anchor accepts.
enum DVPlane { horizontal, vertical, any }

enum DVHand { left, right }

/// What a node is pinned to.
final class DVAnchor {
  /// The first detected plane of [plane] orientation.
  const DVAnchor.plane(DVPlane this.plane)
      : type = DVAnchorType.plane,
        marker = null,
        hand = null,
        id = null;

  /// A tracked image, by the marker's name.
  const DVAnchor.image(String this.marker)
      : type = DVAnchorType.image,
        plane = null,
        hand = null,
        id = null;

  /// A tracked hand.
  const DVAnchor.hand(DVHand this.hand)
      : type = DVAnchorType.hand,
        plane = null,
        marker = null,
        id = null;

  /// A place in the world, kept across launches under [id].
  const DVAnchor.world({required String this.id})
      : type = DVAnchorType.world,
        plane = null,
        marker = null,
        hand = null;

  final DVAnchorType type;
  final DVPlane? plane;
  final String? marker;
  final DVHand? hand;
  final String? id;

  static final RegExp namePattern = RegExp(r'^[A-Za-z0-9_.:\-]{1,128}$');

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.name,
        if (plane != null) 'plane': plane!.name,
        if (marker != null) 'marker': marker,
        if (hand != null) 'hand': hand!.name,
        if (id != null) 'id': id,
      };

  static DVAnchor fromJson(Object? json, String path) {
    if (json is! Map) throw DV3DSceneFormatException(path, 'must be an object');
    final Map<Object?, Object?> map = json;
    T pick<T extends Enum>(List<T> values, Object? name, String at) {
      for (final T v in values) {
        if (v.name == name) return v;
      }
      throw DV3DSceneFormatException(at,
          '${jsonEncode(name)} is not one of ${values.map((T v) => v.name).join(', ')}');
    }

    String name(Object? value, String at) {
      if (value is String && namePattern.hasMatch(value)) return value;
      throw DV3DSceneFormatException(
          at, 'must be 1-128 of A-Z a-z 0-9 _ . : -, not ${jsonEncode(value)}');
    }

    final DVAnchorType type = pick(
      // `shared` is a capability, not a node anchor: a shared anchor is a
      // world anchor whose transform is synced model state.
      DVAnchorType.values.where((DVAnchorType t) => t != DVAnchorType.shared).toList(),
      map['type'],
      '$path.type',
    );
    return switch (type) {
      DVAnchorType.plane =>
        DVAnchor.plane(pick(DVPlane.values, map['plane'], '$path.plane')),
      DVAnchorType.image => DVAnchor.image(name(map['marker'], '$path.marker')),
      DVAnchorType.hand => DVAnchor.hand(pick(DVHand.values, map['hand'], '$path.hand')),
      DVAnchorType.world || DVAnchorType.shared =>
        DVAnchor.world(id: name(map['id'], '$path.id')),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DVAnchor &&
      other.type == type &&
      other.plane == plane &&
      other.marker == marker &&
      other.hand == hand &&
      other.id == id;

  @override
  int get hashCode => Object.hash(type, plane, marker, hand, id);

  @override
  String toString() => 'DVAnchor(${jsonEncode(toJson())})';
}
