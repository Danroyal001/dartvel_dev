/// Scene documents: a scene as data.
///
/// A `DV3DSceneDocument` is what Studio edits, what a content version stores
/// and what a bundle carries to an installed application, so it is read by
/// code that was not the code that wrote it. Three rules follow.
///
/// - **Nothing is lost on the way through.** Every number is written in the
///   shortest form that reads back to the same bits; units, up axis and
///   handedness are stated rather than assumed; node ids are the document's,
///   never regenerated; child order is kept. A key this version does not
///   understand is carried and written back, because a document outlives the
///   version that wrote it.
/// - **A document that cannot be rendered truthfully is refused at decode**,
///   with the path to the bad value: a duplicate id, a node naming an asset
///   the document does not declare, a non-finite or zero-scale transform.
///   Refusing early is what keeps a scene from rendering plausibly with a hole
///   in it.
/// - **Encoding is canonical.** The same document encodes to the same bytes,
///   whatever order its assets were inserted in, so two versions can be
///   compared and an approval digest means something.
library dartvel.scene3d.document;

import 'dart:convert';

import '../media/image.dart';
import 'scene_math.dart';

/// Thrown when a scene document is malformed. [path] names the value, e.g.
/// `nodes[0].children[2].transform.t`.
final class DV3DSceneFormatException implements Exception {
  const DV3DSceneFormatException(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => 'DV3DSceneFormatException: $path: $message';
}

/// The length unit a document's numbers are in.
enum DVSceneUnits {
  meters(1),
  centimeters(0.01),
  millimeters(0.001);

  const DVSceneUnits(this.metersPerUnit);

  final double metersPerUnit;
}

/// Which axis a document treats as up.
enum DVSceneUpAxis { y, z }

/// The handedness of a document's coordinate system.
enum DVSceneHandedness { right, left }

/// What an asset is.
enum DVSceneAssetKind { model, material, environment, texture }

/// Where an asset's bytes come from.
enum DVSceneAssetSource {
  /// Imported by `dartvel build` and shipped in the application bundle.
  bundled,

  /// A key in `DV.FileStorage`: an upload, or an asset delivered after
  /// release.
  stored,

  /// An HTTPS URL. Only fetched from a host the asset policy allows.
  network,
}

/// A reference to a 3D asset, with what is needed to trust it.
///
/// Also the value a `@DVModel.model3dField()` holds, so a model and a scene
/// describe an asset the same way.
final class DVSceneAsset {
  const DVSceneAsset({
    required this.kind,
    required this.source,
    required this.reference,
    this.sha256,
    this.byteLength,
    this.triangles,
    this.poster,
  });

  final DVSceneAssetKind kind;
  final DVSceneAssetSource source;

  /// The bundle key, storage key or URL, depending on [source].
  final String reference;

  /// Lower-case hex SHA-256 of the bytes. Required before a stored or network
  /// asset is loaded (see `DVSceneAssetPolicy`), because a key or a URL says
  /// where bytes are, not which bytes they are.
  final String? sha256;

  final int? byteLength;

  /// Triangles in the model's default scene, as counted at upload or import.
  final int? triangles;

  /// The still shown where the scene cannot render.
  final DVImage? poster;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'source': source.name,
        'reference': reference,
        if (sha256 != null) 'sha256': sha256,
        if (byteLength != null) 'byteLength': byteLength,
        if (triangles != null) 'triangles': triangles,
        if (poster != null) 'poster': poster!.toJson(),
      };

  /// Reads an asset from JSON; null reads as null, as a model field does.
  static DVSceneAsset? fromJson(Object? json, [String path = 'asset']) {
    if (json == null) return null;
    if (json is DVSceneAsset) return json;
    final Map<String, Object?> map = _map(json, path);
    final String reference = _string(map['reference'], '$path.reference');
    if (reference.isEmpty) {
      throw DV3DSceneFormatException('$path.reference', 'must not be empty');
    }
    final Object? digest = map['sha256'];
    if (digest != null && (digest is! String || !_hex64.hasMatch(digest))) {
      throw DV3DSceneFormatException(
          '$path.sha256', 'must be 64 lower-case hex characters');
    }
    return DVSceneAsset(
      kind: _enum(DVSceneAssetKind.values, map['kind'], '$path.kind'),
      source: _enum(DVSceneAssetSource.values, map['source'], '$path.source'),
      reference: reference,
      sha256: digest as String?,
      byteLength: _optionalCount(map['byteLength'], '$path.byteLength'),
      triangles: _optionalCount(map['triangles'], '$path.triangles'),
      poster: DVImage.fromJson(map['poster']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DVSceneAsset && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'DVSceneAsset(${jsonEncode(toJson())})';
}

/// What a scene node is.
enum DVSceneNodeKind { group, model, mesh, camera, light }

/// The procedural shapes a mesh node can be without an asset.
enum DVScenePrimitiveShape { box, sphere, plane }

/// A procedural shape, in the node's local space, centred on its origin.
final class DVScenePrimitive {
  const DVScenePrimitive._(this.shape, this.size);

  /// A box with full extents [size].
  const DVScenePrimitive.box(DVVec3 size) : this._(DVScenePrimitiveShape.box, size);

  /// A sphere of [radius].
  DVScenePrimitive.sphere(double radius)
      : this._(DVScenePrimitiveShape.sphere, DVVec3(radius, radius, radius));

  /// A flat plane in local XZ, [width] along X and [depth] along Z.
  DVScenePrimitive.plane(double width, double depth)
      : this._(DVScenePrimitiveShape.plane, DVVec3(width, 0, depth));

  final DVScenePrimitiveShape shape;

  /// Full extents for a box or plane; the radius in every component for a
  /// sphere.
  final DVVec3 size;

  double get radius => size.x;

  DVAabb get localBounds => shape == DVScenePrimitiveShape.sphere
      ? DVAabb(-size, size)
      : DVAabb(size * -0.5, size * 0.5);

  Map<String, Object?> toJson() => switch (shape) {
        DVScenePrimitiveShape.box => <String, Object?>{
            'shape': 'box',
            'size': size.toList(),
          },
        DVScenePrimitiveShape.sphere => <String, Object?>{
            'shape': 'sphere',
            'radius': radius,
          },
        DVScenePrimitiveShape.plane => <String, Object?>{
            'shape': 'plane',
            'width': size.x,
            'depth': size.z,
          },
      };

  static DVScenePrimitive fromJson(Object? json, String path) {
    final Map<String, Object?> map = _map(json, path);
    final DVScenePrimitiveShape shape =
        _enum(DVScenePrimitiveShape.values, map['shape'], '$path.shape');
    DVScenePrimitive built;
    switch (shape) {
      case DVScenePrimitiveShape.box:
        built = DVScenePrimitive.box(_vec3(map['size'], '$path.size'));
      case DVScenePrimitiveShape.sphere:
        built = DVScenePrimitive.sphere(_number(map['radius'], '$path.radius'));
      case DVScenePrimitiveShape.plane:
        built = DVScenePrimitive.plane(
          _number(map['width'], '$path.width'),
          _number(map['depth'], '$path.depth'),
        );
    }
    final DVVec3 s = built.size;
    if (s.x < 0 || s.y < 0 || s.z < 0 ||
        (shape == DVScenePrimitiveShape.sphere && s.x == 0)) {
      throw DV3DSceneFormatException(path, 'a shape cannot have a negative size');
    }
    return built;
  }
}

/// The light types.
enum DVSceneLightType { directional, point, spot }

/// A light's parameters.
final class DVSceneLight {
  const DVSceneLight.directional({
    required DVVec3 this.direction,
    this.color = 0xFFFFFF,
    this.intensity = 1,
    this.castShadows = false,
  })  : type = DVSceneLightType.directional,
        range = null,
        innerConeDegrees = null,
        outerConeDegrees = null;

  const DVSceneLight.point({
    this.color = 0xFFFFFF,
    this.intensity = 1,
    this.range,
    this.castShadows = false,
  })  : type = DVSceneLightType.point,
        direction = null,
        innerConeDegrees = null,
        outerConeDegrees = null;

  const DVSceneLight.spot({
    required DVVec3 this.direction,
    this.color = 0xFFFFFF,
    this.intensity = 1,
    this.range,
    this.innerConeDegrees = 0,
    this.outerConeDegrees = 45,
    this.castShadows = false,
  }) : type = DVSceneLightType.spot;

  const DVSceneLight._({
    required this.type,
    required this.direction,
    required this.color,
    required this.intensity,
    required this.range,
    required this.innerConeDegrees,
    required this.outerConeDegrees,
    required this.castShadows,
  });

  final DVSceneLightType type;

  /// The direction light travels, for directional and spot lights.
  final DVVec3? direction;

  /// 0xRRGGBB.
  final int color;
  final double intensity;
  final double? range;
  final double? innerConeDegrees;
  final double? outerConeDegrees;
  final bool castShadows;

  DVSceneLight withShadows([bool cast = true]) => DVSceneLight._(
        type: type,
        direction: direction,
        color: color,
        intensity: intensity,
        range: range,
        innerConeDegrees: innerConeDegrees,
        outerConeDegrees: outerConeDegrees,
        castShadows: cast,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.name,
        if (direction != null) 'direction': direction!.toList(),
        'color': color,
        'intensity': intensity,
        if (range != null) 'range': range,
        if (innerConeDegrees != null) 'innerCone': innerConeDegrees,
        if (outerConeDegrees != null) 'outerCone': outerConeDegrees,
        if (castShadows) 'castShadows': true,
      };

  static DVSceneLight fromJson(Object? json, String path) {
    final Map<String, Object?> map = _map(json, path);
    final DVSceneLightType type =
        _enum(DVSceneLightType.values, map['type'], '$path.type');
    final Object? rawColor = map['color'] ?? 0xFFFFFF;
    if (rawColor is! int || rawColor < 0 || rawColor > 0xFFFFFF) {
      throw DV3DSceneFormatException('$path.color', 'must be 0xRRGGBB');
    }
    final bool needsDirection = type != DVSceneLightType.point;
    final DVVec3? direction = needsDirection
        ? _vec3(map['direction'], '$path.direction')
        : null;
    if (direction != null && direction == DVVec3.zero) {
      throw DV3DSceneFormatException(
          '$path.direction', 'a light cannot point nowhere');
    }
    return DVSceneLight._(
      type: type,
      direction: direction,
      color: rawColor,
      intensity: _number(map['intensity'] ?? 1, '$path.intensity'),
      range: map['range'] == null ? null : _number(map['range'], '$path.range'),
      innerConeDegrees: map['innerCone'] == null
          ? null
          : _number(map['innerCone'], '$path.innerCone'),
      outerConeDegrees: map['outerCone'] == null
          ? null
          : _number(map['outerCone'], '$path.outerCone'),
      castShadows: _bool(map['castShadows'] ?? false, '$path.castShadows'),
    );
  }
}

/// A camera's projection, and optionally the orbit it is controlled by.
final class DVSceneCameraData {
  const DVSceneCameraData.perspective({
    this.fovYDegrees = 45,
    this.near = 0.1,
    this.far = 1000,
  })  : orbitTarget = null,
        orbitDistance = null,
        controls = false;

  /// A camera orbiting [target] at [distance]; with [controls] a viewport
  /// lets the user drag and pinch it.
  const DVSceneCameraData.orbit({
    DVVec3 target = DVVec3.zero,
    required double distance,
    this.controls = false,
    this.fovYDegrees = 45,
    this.near = 0.1,
    this.far = 1000,
  })  : orbitTarget = target,
        orbitDistance = distance;

  const DVSceneCameraData._({
    required this.fovYDegrees,
    required this.near,
    required this.far,
    required this.orbitTarget,
    required this.orbitDistance,
    required this.controls,
  });

  final double fovYDegrees;
  final double near;
  final double far;
  final DVVec3? orbitTarget;
  final double? orbitDistance;
  final bool controls;

  bool get isOrbit => orbitDistance != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'projection': 'perspective',
        'fovY': fovYDegrees,
        'near': near,
        'far': far,
        if (isOrbit)
          'orbit': <String, Object?>{
            'target': orbitTarget!.toList(),
            'distance': orbitDistance,
            if (controls) 'controls': true,
          },
      };

  static DVSceneCameraData fromJson(Object? json, String path) {
    final Map<String, Object?> map = _map(json, path);
    if (map['projection'] != 'perspective') {
      throw DV3DSceneFormatException(
          '$path.projection', "only 'perspective' is supported");
    }
    final double fov = _number(map['fovY'] ?? 45, '$path.fovY');
    final double near = _number(map['near'] ?? 0.1, '$path.near');
    final double far = _number(map['far'] ?? 1000, '$path.far');
    if (fov <= 0 || fov >= 180) {
      throw DV3DSceneFormatException('$path.fovY', 'must be between 0 and 180');
    }
    if (near <= 0 || far <= near) {
      throw DV3DSceneFormatException(
          '$path.near', 'near must be positive and less than far');
    }
    final Object? orbit = map['orbit'];
    if (orbit == null) {
      return DVSceneCameraData.perspective(fovYDegrees: fov, near: near, far: far);
    }
    final Map<String, Object?> o = _map(orbit, '$path.orbit');
    final double distance = _number(o['distance'], '$path.orbit.distance');
    if (distance <= 0) {
      throw DV3DSceneFormatException(
          '$path.orbit.distance', 'must be positive');
    }
    return DVSceneCameraData._(
      fovYDegrees: fov,
      near: near,
      far: far,
      orbitTarget: _vec3(o['target'] ?? const <double>[0, 0, 0], '$path.orbit.target'),
      orbitDistance: distance,
      controls: _bool(o['controls'] ?? false, '$path.orbit.controls'),
    );
  }
}

/// One node in a scene document.
final class DVSceneNodeData {
  DVSceneNodeData({
    required this.id,
    required this.kind,
    this.name,
    DVTransform? transform,
    this.visible = true,
    this.asset,
    this.material,
    this.primitive,
    this.light,
    this.camera,
    List<DVSceneNodeData> children = const <DVSceneNodeData>[],
    Map<String, Object?> extra = const <String, Object?>{},
  })  : transform = transform ?? DVTransform.identity,
        children = List<DVSceneNodeData>.unmodifiable(children),
        extra = Map<String, Object?>.unmodifiable(extra);

  factory DVSceneNodeData.group({
    required String id,
    String? name,
    DVTransform? transform,
    bool visible = true,
    List<DVSceneNodeData> children = const <DVSceneNodeData>[],
  }) =>
      DVSceneNodeData(
          id: id,
          kind: DVSceneNodeKind.group,
          name: name,
          transform: transform,
          visible: visible,
          children: children);

  factory DVSceneNodeData.model({
    required String id,
    required String asset,
    String? name,
    String? material,
    DVTransform? transform,
    bool visible = true,
    List<DVSceneNodeData> children = const <DVSceneNodeData>[],
  }) =>
      DVSceneNodeData(
          id: id,
          kind: DVSceneNodeKind.model,
          asset: asset,
          name: name,
          material: material,
          transform: transform,
          visible: visible,
          children: children);

  factory DVSceneNodeData.mesh({
    required String id,
    required DVScenePrimitive primitive,
    String? name,
    String? material,
    DVTransform? transform,
    bool visible = true,
    List<DVSceneNodeData> children = const <DVSceneNodeData>[],
  }) =>
      DVSceneNodeData(
          id: id,
          kind: DVSceneNodeKind.mesh,
          primitive: primitive,
          name: name,
          material: material,
          transform: transform,
          visible: visible,
          children: children);

  factory DVSceneNodeData.camera({
    required String id,
    required DVSceneCameraData camera,
    String? name,
    DVTransform? transform,
  }) =>
      DVSceneNodeData(
          id: id,
          kind: DVSceneNodeKind.camera,
          camera: camera,
          name: name,
          transform: transform);

  factory DVSceneNodeData.light({
    required String id,
    required DVSceneLight light,
    String? name,
    DVTransform? transform,
    bool visible = true,
  }) =>
      DVSceneNodeData(
          id: id,
          kind: DVSceneNodeKind.light,
          light: light,
          name: name,
          transform: transform,
          visible: visible);

  /// Stable within its document; what Studio, picking, sync bindings and a
  /// renderer's resource cache all key on.
  final String id;
  final DVSceneNodeKind kind;
  final String? name;
  final DVTransform transform;
  final bool visible;

  /// A key into the document's assets, for a model node.
  final String? asset;

  /// A key into the document's assets naming a material.
  final String? material;
  final DVScenePrimitive? primitive;
  final DVSceneLight? light;
  final DVSceneCameraData? camera;
  final List<DVSceneNodeData> children;

  /// Keys this version did not understand, written back unchanged.
  final Map<String, Object?> extra;

  static final RegExp idPattern = RegExp(r'^[A-Za-z0-9_.:\-/#]{1,128}$');

  static const Set<String> _known = <String>{
    'id', 'kind', 'name', 'transform', 'visible', 'asset', 'material',
    'primitive', 'light', 'camera', 'children',
  };

  DVSceneNodeData copyWith({
    DVTransform? transform,
    bool? visible,
    List<DVSceneNodeData>? children,
  }) =>
      DVSceneNodeData(
        id: id,
        kind: kind,
        name: name,
        transform: transform ?? this.transform,
        visible: visible ?? this.visible,
        asset: asset,
        material: material,
        primitive: primitive,
        light: light,
        camera: camera,
        children: children ?? this.children,
        extra: extra,
      );

  Map<String, Object?> toJson() {
    final Map<String, Object?> t = <String, Object?>{
      if (transform.translation != DVVec3.zero)
        't': transform.translation.toList(),
      if (transform.rotation != DVQuat.identity)
        'r': transform.rotation.toList(),
      if (transform.scale != DVVec3.one) 's': transform.scale.toList(),
    };
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      if (name != null) 'name': name,
      if (t.isNotEmpty) 'transform': t,
      if (!visible) 'visible': false,
      if (asset != null) 'asset': asset,
      if (material != null) 'material': material,
      if (primitive != null) 'primitive': primitive!.toJson(),
      if (light != null) 'light': light!.toJson(),
      if (camera != null) 'camera': camera!.toJson(),
      if (children.isNotEmpty)
        'children': <Object?>[for (final DVSceneNodeData c in children) c.toJson()],
      ...extra,
    };
  }

  static DVSceneNodeData fromJson(Object? json, String path) {
    final Map<String, Object?> map = _map(json, path);
    final Object? id = map['id'];
    if (id is! String || !idPattern.hasMatch(id)) {
      throw DV3DSceneFormatException('$path.id',
          'a node id must be 1-128 of A-Z a-z 0-9 _ . : - / #, not ${jsonEncode(id)}');
    }
    final DVSceneNodeKind kind =
        _enum(DVSceneNodeKind.values, map['kind'], '$path.kind');
    final Object? rawChildren = map['children'];
    if (rawChildren != null && rawChildren is! List) {
      throw DV3DSceneFormatException('$path.children', 'must be a list');
    }
    final List<Object?> childList = (rawChildren as List<Object?>?) ?? const <Object?>[];
    final Object? name = map['name'];
    if (name != null && name is! String) {
      throw DV3DSceneFormatException('$path.name', 'must be a string');
    }
    final DVSceneNodeData node = DVSceneNodeData(
      id: id,
      kind: kind,
      name: name as String?,
      transform: _transform(map['transform'], '$path.transform'),
      visible: _bool(map['visible'] ?? true, '$path.visible'),
      asset: map['asset'] == null ? null : _string(map['asset'], '$path.asset'),
      material: map['material'] == null
          ? null
          : _string(map['material'], '$path.material'),
      primitive: map['primitive'] == null
          ? null
          : DVScenePrimitive.fromJson(map['primitive'], '$path.primitive'),
      light: map['light'] == null
          ? null
          : DVSceneLight.fromJson(map['light'], '$path.light'),
      camera: map['camera'] == null
          ? null
          : DVSceneCameraData.fromJson(map['camera'], '$path.camera'),
      children: <DVSceneNodeData>[
        for (int i = 0; i < childList.length; i++)
          DVSceneNodeData.fromJson(childList[i], '$path.children[$i]'),
      ],
      extra: <String, Object?>{
        for (final MapEntry<String, Object?> e in map.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
    _checkPayload(node, path);
    return node;
  }

  static void _checkPayload(DVSceneNodeData node, String path) {
    String? missing;
    switch (node.kind) {
      case DVSceneNodeKind.model:
        if (node.asset == null) missing = 'asset';
      case DVSceneNodeKind.mesh:
        if (node.primitive == null) missing = 'primitive';
      case DVSceneNodeKind.camera:
        if (node.camera == null) missing = 'camera';
      case DVSceneNodeKind.light:
        if (node.light == null) missing = 'light';
      case DVSceneNodeKind.group:
        break;
    }
    if (missing != null) {
      throw DV3DSceneFormatException(
          '$path.$missing', 'a ${node.kind.name} node needs a $missing');
    }
  }
}

/// A scene, as a document.
final class DV3DSceneDocument {
  DV3DSceneDocument({
    required this.id,
    this.units = DVSceneUnits.meters,
    this.upAxis = DVSceneUpAxis.y,
    this.handedness = DVSceneHandedness.right,
    this.environment = studioEnvironment,
    this.poster,
    Map<String, DVSceneAsset> assets = const <String, DVSceneAsset>{},
    List<DVSceneNodeData> nodes = const <DVSceneNodeData>[],
    Map<String, Object?> extra = const <String, Object?>{},
  })  : assets = Map<String, DVSceneAsset>.unmodifiable(<String, DVSceneAsset>{
          for (final String key in assets.keys.toList()..sort()) key: assets[key]!,
        }),
        nodes = List<DVSceneNodeData>.unmodifiable(nodes),
        extra = Map<String, Object?>.unmodifiable(extra) {
    _validate();
  }

  /// The document format this runtime reads and writes.
  static const int format = 1;

  /// The procedural image-based-lighting environment every scene can use
  /// without an asset.
  static const String studioEnvironment = 'studio';

  final String id;
  final DVSceneUnits units;
  final DVSceneUpAxis upAxis;
  final DVSceneHandedness handedness;

  /// [studioEnvironment], an asset key of kind environment, or null for none.
  final String? environment;
  final DVImage? poster;

  /// Sorted by key.
  final Map<String, DVSceneAsset> assets;
  final List<DVSceneNodeData> nodes;
  final Map<String, Object?> extra;

  static const Set<String> _known = <String>{
    'format', 'id', 'units', 'upAxis', 'handedness', 'environment', 'poster',
    'assets', 'nodes',
  };

  /// Every node id, depth first in document order.
  List<String> nodeIds() => <String>[
        for (final DVSceneNodeData n in walk()) n.id,
      ];

  /// Every node, depth first in document order.
  Iterable<DVSceneNodeData> walk() sync* {
    Iterable<DVSceneNodeData> visit(DVSceneNodeData node) sync* {
      yield node;
      for (final DVSceneNodeData child in node.children) {
        yield* visit(child);
      }
    }

    for (final DVSceneNodeData root in nodes) {
      yield* visit(root);
    }
  }

  DVSceneNodeData? find(String nodeId) {
    for (final DVSceneNodeData n in walk()) {
      if (n.id == nodeId) return n;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'format': format,
        'id': id,
        'units': units.name,
        'upAxis': upAxis.name,
        'handedness': handedness.name,
        if (environment != null) 'environment': environment,
        if (poster != null) 'poster': poster!.toJson(),
        'assets': <String, Object?>{
          for (final MapEntry<String, DVSceneAsset> e in assets.entries)
            e.key: e.value.toJson(),
        },
        'nodes': <Object?>[for (final DVSceneNodeData n in nodes) n.toJson()],
        ...extra,
      };

  String encode() => jsonEncode(toJson());

  static DV3DSceneDocument decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (error) {
      throw DV3DSceneFormatException(r'$', 'not JSON: ${error.message}');
    }
    return DV3DSceneDocument.fromJson(json);
  }

  factory DV3DSceneDocument.fromJson(Object? json) {
    final Map<String, Object?> map = _map(json, r'$');
    if (map['format'] != format) {
      throw DV3DSceneFormatException('format',
          'this runtime reads format $format, not ${jsonEncode(map['format'])}');
    }
    final String id = _string(map['id'], 'id');
    final Map<String, Object?> rawAssets =
        _map(map['assets'] ?? const <String, Object?>{}, 'assets');
    final Object? rawNodes = map['nodes'] ?? const <Object?>[];
    if (rawNodes is! List) {
      throw const DV3DSceneFormatException('nodes', 'must be a list');
    }
    final Object? environment =
        map.containsKey('environment') ? map['environment'] : null;
    if (environment != null && environment is! String) {
      throw const DV3DSceneFormatException('environment', 'must be a string');
    }
    return DV3DSceneDocument(
      id: id,
      units: _enum(DVSceneUnits.values, map['units'] ?? 'meters', 'units'),
      upAxis: _enum(DVSceneUpAxis.values, map['upAxis'] ?? 'y', 'upAxis'),
      handedness: _enum(
          DVSceneHandedness.values, map['handedness'] ?? 'right', 'handedness'),
      environment: environment as String?,
      poster: DVImage.fromJson(map['poster']),
      assets: <String, DVSceneAsset>{
        for (final MapEntry<String, Object?> e in rawAssets.entries)
          e.key: DVSceneAsset.fromJson(e.value, 'assets.${e.key}')!,
      },
      nodes: <DVSceneNodeData>[
        for (int i = 0; i < rawNodes.length; i++)
          DVSceneNodeData.fromJson(rawNodes[i], 'nodes[$i]'),
      ],
      extra: <String, Object?>{
        for (final MapEntry<String, Object?> e in map.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      },
    );
  }

  void _validate() {
    if (id.isEmpty) {
      throw const DV3DSceneFormatException('id', 'must not be empty');
    }
    final String? env = environment;
    if (env != null && env != studioEnvironment) {
      final DVSceneAsset? asset = assets[env];
      if (asset == null || asset.kind != DVSceneAssetKind.environment) {
        throw DV3DSceneFormatException('environment',
            "'$env' is neither '$studioEnvironment' nor a declared environment asset");
      }
    }
    final Set<String> seen = <String>{};
    void check(DVSceneNodeData node, String path) {
      if (!DVSceneNodeData.idPattern.hasMatch(node.id)) {
        throw DV3DSceneFormatException('$path.id', "'${node.id}' is not a valid node id");
      }
      if (!seen.add(node.id)) {
        throw DV3DSceneFormatException(
            '$path.id', "'${node.id}' is used by more than one node");
      }
      DVSceneNodeData._checkPayload(node, path);
      _checkTransform(node.transform, '$path.transform');
      void reference(String? key, DVSceneAssetKind kind, String field) {
        if (key == null) return;
        final DVSceneAsset? asset = assets[key];
        if (asset == null) {
          throw DV3DSceneFormatException('$path.$field',
              "'$key' is not declared in the document's assets");
        }
        if (asset.kind != kind) {
          throw DV3DSceneFormatException('$path.$field',
              "'$key' is a ${asset.kind.name}, not a ${kind.name}");
        }
      }

      reference(node.asset, DVSceneAssetKind.model, 'asset');
      reference(node.material, DVSceneAssetKind.material, 'material');
      for (int i = 0; i < node.children.length; i++) {
        check(node.children[i], '$path.children[$i]');
      }
    }

    for (int i = 0; i < nodes.length; i++) {
      check(nodes[i], 'nodes[$i]');
    }
  }
}

// --- reading helpers ---------------------------------------------------------

Map<String, Object?> _map(Object? json, String path) {
  if (json is Map) {
    for (final Object? key in json.keys) {
      if (key is! String) {
        throw DV3DSceneFormatException(path, 'object keys must be strings');
      }
    }
    return json.cast<String, Object?>();
  }
  throw DV3DSceneFormatException(path, 'must be an object');
}

String _string(Object? value, String path) {
  if (value is String) return value;
  throw DV3DSceneFormatException(path, 'must be a string');
}

bool _bool(Object? value, String path) {
  if (value is bool) return value;
  throw DV3DSceneFormatException(path, 'must be true or false');
}

double _number(Object? value, String path) {
  if (value is num && value.isFinite) return value.toDouble();
  throw DV3DSceneFormatException(path, 'not a finite number: ${jsonEncode(value)}');
}

int? _optionalCount(Object? value, String path) {
  if (value == null) return null;
  if (value is int && value >= 0) return value;
  throw DV3DSceneFormatException(path, 'must be a non-negative integer');
}

T _enum<T extends Enum>(List<T> values, Object? name, String path) {
  for (final T value in values) {
    if (value.name == name) return value;
  }
  throw DV3DSceneFormatException(path,
      '${jsonEncode(name)} is not one of ${values.map((T v) => v.name).join(', ')}');
}

List<double> _numbers(Object? value, int count, String path) {
  if (value is! List || value.length != count) {
    throw DV3DSceneFormatException(path, 'must be a list of $count numbers');
  }
  return <double>[
    for (int i = 0; i < count; i++)
      if (value[i] is num && (value[i] as num).isFinite)
        (value[i] as num).toDouble()
      else
        throw DV3DSceneFormatException(
            path, 'not a finite number at [$i]: ${jsonEncode(value[i])}'),
  ];
}

DVVec3 _vec3(Object? value, String path) {
  final List<double> n = _numbers(value, 3, path);
  return DVVec3(n[0], n[1], n[2]);
}

DVTransform _transform(Object? json, String path) {
  if (json == null) return DVTransform.identity;
  final Map<String, Object?> map = _map(json, path);
  final DVTransform transform = DVTransform(
    translation: map['t'] == null ? DVVec3.zero : _vec3(map['t'], '$path.t'),
    rotation: map['r'] == null
        ? DVQuat.identity
        : (() {
            final List<double> q = _numbers(map['r'], 4, '$path.r');
            return DVQuat(q[0], q[1], q[2], q[3]);
          })(),
    scale: map['s'] == null ? DVVec3.one : _vec3(map['s'], '$path.s'),
  );
  _checkTransform(transform, path);
  return transform;
}

void _checkTransform(DVTransform transform, String path) {
  if (!transform.translation.isFinite) {
    throw DV3DSceneFormatException('$path.t', 'not a finite number');
  }
  if (!transform.rotation.isFinite ||
      (transform.rotation.length - 1).abs() > 1e-6) {
    throw DV3DSceneFormatException(
        '$path.r', 'a rotation must be a unit quaternion');
  }
  final DVVec3 s = transform.scale;
  if (!s.isFinite || s.x == 0 || s.y == 0 || s.z == 0) {
    throw DV3DSceneFormatException(
        '$path.s', 'a scale must be finite and non-zero on every axis');
  }
}
