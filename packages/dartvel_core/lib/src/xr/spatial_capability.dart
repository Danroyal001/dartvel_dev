/// What a target can do in space.
library dartvel.xr.capability;

import '../scene3d/scene_anchor.dart';
import '../scene3d/scene_math.dart';

/// How an immersive space shows the world around the user.
enum DVImmersion {
  /// The real world, through the headset's cameras, with the scene in it.
  passthrough,

  /// Only the scene.
  full,
}

/// The two ways of presenting a scene in space that are new kinds. A panel is
/// an ordinary window and needs nothing here.
enum DVSpatialSpaceKind { volume, immersive }

/// The inputs a target delivers. Which exist is reported, never assumed.
enum DVSpatialInput { hands, controllers, gaze, voice }

enum DVSpatialPersistenceKind { full, bounded, none }

/// Whether the OS keeps pinned panels across reboot: all of them, a bounded
/// number, or none. Dartvel remembers no placements of its own.
final class DVSpatialPersistence {
  const DVSpatialPersistence._(this.kind, this._limit);

  static const DVSpatialPersistence full =
      DVSpatialPersistence._(DVSpatialPersistenceKind.full, null);
  static const DVSpatialPersistence none =
      DVSpatialPersistence._(DVSpatialPersistenceKind.none, null);

  /// The OS restores at most [limit] panels.
  const DVSpatialPersistence.bounded(int limit)
      : kind = DVSpatialPersistenceKind.bounded,
        _limit = limit;

  final DVSpatialPersistenceKind kind;
  final int? _limit;

  int? get limit {
    final int? l = _limit;
    if (kind == DVSpatialPersistenceKind.bounded && (l == null || l < 1)) {
      throw ArgumentError.value(l, 'limit', 'a bounded persistence keeps at least one panel');
    }
    return l;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        if (kind == DVSpatialPersistenceKind.bounded) 'limit': limit,
      };

  @override
  bool operator ==(Object other) =>
      other is DVSpatialPersistence && other.kind == kind && other._limit == _limit;

  @override
  int get hashCode => Object.hash(kind, _limit);

  @override
  String toString() => 'DVSpatialPersistence(${toJson()})';
}

/// The size a volume asks for, in metres. A hint: the OS decides.
final class DVVolumeOptions {
  const DVVolumeOptions({required this.size});

  /// [size], refused unless finite and positive on every axis.
  factory DVVolumeOptions.checked(DVVec3 size) {
    if (!size.isFinite || size.x <= 0 || size.y <= 0 || size.z <= 0) {
      throw ArgumentError.value(size, 'size', 'must be finite and positive on every axis');
    }
    return DVVolumeOptions(size: size);
  }

  final DVVec3 size;
}

/// `DV.Window.capability.spatial`: null on every target that is not a headset
/// or glasses.
///
/// The one place application code may branch -- to decide whether to *offer*
/// a spatial control, never whether `open()` will work.
final class DVSpatialCapability {
  const DVSpatialCapability({
    this.panels = false,
    this.volumes = false,
    this.immersive = false,
    this.passthrough = false,
    this.persistence = DVSpatialPersistence.none,
    this.input = const <DVSpatialInput>{},
    this.anchors = const <DVAnchorType>{},
    this.occlusion = false,
    this.sceneMesh = false,
  });

  /// A headset that can present all three ways. What `DV.Test.fakeXR` is
  /// usually given.
  factory DVSpatialCapability.headset() => const DVSpatialCapability(
        panels: true,
        volumes: true,
        immersive: true,
        passthrough: true,
        persistence: DVSpatialPersistence.full,
        input: <DVSpatialInput>{
          DVSpatialInput.hands,
          DVSpatialInput.controllers,
          DVSpatialInput.gaze,
          DVSpatialInput.voice,
        },
        anchors: <DVAnchorType>{
          DVAnchorType.plane,
          DVAnchorType.image,
          DVAnchorType.hand,
          DVAnchorType.world,
        },
        occlusion: true,
        sceneMesh: true,
      );

  /// Glasses: HUD-class panels only. No volumes and no immersive space.
  factory DVSpatialCapability.glasses() => const DVSpatialCapability(
        panels: true,
        input: <DVSpatialInput>{DVSpatialInput.voice},
      );

  final bool panels;
  final bool volumes;
  final bool immersive;
  final bool passthrough;
  final DVSpatialPersistence persistence;
  final Set<DVSpatialInput> input;
  final Set<DVAnchorType> anchors;
  final bool occlusion;
  final bool sceneMesh;

  bool supports(DVSpatialSpaceKind kind) => switch (kind) {
        DVSpatialSpaceKind.volume => volumes,
        DVSpatialSpaceKind.immersive => immersive,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'panels': panels,
        'volumes': volumes,
        'immersive': immersive,
        'passthrough': passthrough,
        'persistence': persistence.toJson(),
        'input': <String>[for (final DVSpatialInput i in DVSpatialInput.values) if (input.contains(i)) i.name],
        'anchors': <String>[for (final DVAnchorType a in DVAnchorType.values) if (anchors.contains(a)) a.name],
        'occlusion': occlusion,
        'sceneMesh': sceneMesh,
      };

  /// Reads the payload `xr.capability.query` returned.
  ///
  /// Strict in the direction that matters: a field not reported is false, and
  /// a member this version does not know is dropped rather than claimed. A
  /// payload that is not a report at all throws [FormatException], which the
  /// caller reports as the binding defect it is (`DV-XR-006`).
  static DVSpatialCapability fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('a spatial capability report must be an object, not ${json.runtimeType}');
    }
    bool flag(String key) {
      final Object? v = json[key];
      if (v == null) return false;
      if (v is bool) return v;
      throw FormatException("'$key' must be true or false, not $v");
    }

    Set<T> members<T extends Enum>(String key, List<T> values) {
      final Object? raw = json[key];
      if (raw == null) return <T>{};
      if (raw is! List) throw FormatException("'$key' must be a list");
      return <T>{
        for (final T v in values)
          if (raw.contains(v.name)) v,
      };
    }

    DVSpatialPersistence persistence = DVSpatialPersistence.none;
    final Object? p = json['persistence'];
    if (p != null) {
      if (p is! Map) throw const FormatException("'persistence' must be an object");
      switch (p['kind']) {
        case 'full':
          persistence = DVSpatialPersistence.full;
        case 'bounded':
          final Object? limit = p['limit'];
          if (limit is! int || limit < 1) {
            throw FormatException("a bounded persistence needs a positive 'limit', not $limit");
          }
          persistence = DVSpatialPersistence.bounded(limit);
        case 'none':
          persistence = DVSpatialPersistence.none;
        default:
          // An unknown kind promises nothing.
          persistence = DVSpatialPersistence.none;
      }
    }
    return DVSpatialCapability(
      panels: flag('panels'),
      volumes: flag('volumes'),
      immersive: flag('immersive'),
      passthrough: flag('passthrough'),
      persistence: persistence,
      input: members('input', DVSpatialInput.values),
      anchors: members('anchors', DVAnchorType.values),
      occlusion: flag('occlusion'),
      sceneMesh: flag('sceneMesh'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DVSpatialCapability && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;

  @override
  String toString() => 'DVSpatialCapability(${toJson()})';
}
