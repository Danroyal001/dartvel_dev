/// Scene nodes: typed scene objects, not widgets.
///
/// A scene graph and a widget tree have different lifecycles, so a node has
/// no `build` method and never enters the element tree. `DVBox.scene` is the
/// one place the two meet: it resolves these nodes into a
/// `DV3DSceneDocument` on each build and hands that to the scene runtime.
///
/// Modifiers follow the fluent style of `DVModifier` and take a plain value
/// or a signal. A signal is read when the box builds, which subscribes the
/// element that owns it, so changing the signal rebuilds the box and the
/// next frame draws the node where the signal now says -- a turntable is one
/// signal and no ticker.
library dartvel_flutter.scene3d.nodes;

import 'package:flutter/foundation.dart';

import '../../dartvel_flutter.dart';

final class _Props {
  const _Props({
    this.id,
    this.position,
    this.rotation,
    this.rotationY,
    this.scale,
    this.visible,
    this.onTap,
    this.material,
    this.anchor,
    this.onGrab,
    this.onRelease,
  });

  final String? id;
  final Object? position;
  final Object? rotation;
  final Object? rotationY;
  final Object? scale;
  final Object? visible;
  final VoidCallback? onTap;
  final DVSceneAsset? material;
  final DVAnchor? anchor;
  final VoidCallback? onGrab;
  final VoidCallback? onRelease;

  _Props copyWith({
    String? id,
    Object? position,
    Object? rotation,
    Object? rotationY,
    Object? scale,
    Object? visible,
    VoidCallback? onTap,
    DVSceneAsset? material,
    DVAnchor? anchor,
    VoidCallback? onGrab,
    VoidCallback? onRelease,
  }) =>
      _Props(
        id: id ?? this.id,
        position: position ?? this.position,
        rotation: rotation ?? this.rotation,
        rotationY: rotationY ?? this.rotationY,
        scale: scale ?? this.scale,
        visible: visible ?? this.visible,
        onTap: onTap ?? this.onTap,
        material: material ?? this.material,
        anchor: anchor ?? this.anchor,
        onGrab: onGrab ?? this.onGrab,
        onRelease: onRelease ?? this.onRelease,
      );
}

Object? _read(Object? value) => value is DVReadableSignal ? value.value : value;

/// A node in a [DVScene].
abstract class DVSceneNode {
  const DVSceneNode._(this._props, this.children);

  final _Props _props;

  /// Child nodes, placed in this node's space.
  final List<DVSceneNode> children;

  /// The id this node was given with `.id(...)`, if any.
  String? get explicitId => _props.id;

  /// The name derived ids use for this kind: `node`, `model3d`, `mesh`,
  /// `camera` or `light`.
  String get kindName;

  DVSceneNode _copy(_Props props);

  DVSceneNodeData _data(
    String id,
    DVTransform transform,
    bool visible,
    List<DVSceneNodeData> children,
    String Function(DVSceneAsset asset) assetKey,
  );

  DVTransform _transform() {
    final DVVec3 position = (_read(_props.position) as DVVec3?) ?? DVVec3.zero;
    DVQuat rotation = (_read(_props.rotation) as DVQuat?) ?? DVQuat.identity;
    final num? yaw = _read(_props.rotationY) as num?;
    if (yaw != null) {
      rotation = rotation * DVQuat.axisAngle(DVVec3.up, yaw.toDouble());
    }
    final Object? scale = _read(_props.scale);
    return DVTransform(
      translation: position,
      rotation: rotation,
      scale: scale is num
          ? DVVec3(scale.toDouble(), scale.toDouble(), scale.toDouble())
          : (scale as DVVec3?) ?? DVVec3.one,
    );
  }
}

void _check<T>(Object? value, String modifier, String expected) {
  if (value is T || value is DVReadableSignal<T>) return;
  throw ArgumentError.value(value, modifier,
      'expected $expected or a signal of it, not ${value.runtimeType}');
}

/// The modifiers every scene node takes.
mixin DVSceneNodeModifiers<Self extends DVSceneNode> on DVSceneNode {
  /// A stable id: what taps, sync bindings, Studio and a renderer's resource
  /// cache key on. Nodes without one get an id from their position in the
  /// scene, which is stable as long as the nodes before them are.
  Self id(String id) => _copy(_props.copyWith(id: id)) as Self;

  /// A [DVVec3] or a signal of one, in metres.
  Self position(Object value) {
    _check<DVVec3>(value, 'position', 'a DVVec3');
    return _copy(_props.copyWith(position: value)) as Self;
  }

  /// A [DVQuat] or a signal of one.
  Self rotation(Object value) {
    _check<DVQuat>(value, 'rotation', 'a DVQuat');
    return _copy(_props.copyWith(rotation: value)) as Self;
  }

  /// Radians about the up axis, or a signal of them, applied after
  /// [rotation].
  Self rotationY(Object radians) {
    _check<num>(radians, 'rotationY', 'a number of radians');
    return _copy(_props.copyWith(rotationY: radians)) as Self;
  }

  /// A uniform number, a [DVVec3], or a signal of either.
  Self scale(Object value) {
    if (value is! num && value is! DVReadableSignal<num>) {
      _check<DVVec3>(value, 'scale', 'a number or a DVVec3');
    }
    return _copy(_props.copyWith(scale: value)) as Self;
  }

  /// A bool or a signal of one. A hidden node is neither drawn nor tapped,
  /// and neither are its children.
  Self visible(Object value) {
    _check<bool>(value, 'visible', 'a bool');
    return _copy(_props.copyWith(visible: value)) as Self;
  }

  /// Called when this node, or a child with no handler of its own, is the
  /// nearest thing under a tap.
  Self onTap(VoidCallback handler) =>
      _copy(_props.copyWith(onTap: handler)) as Self;

  /// Pins this node to something in the real world. Where the target cannot
  /// honour [anchor] -- every target that is not presenting the scene in
  /// space -- the node stays at the scene origin and `DV-XR-002` says so.
  Self anchor(DVAnchor anchor) => _copy(_props.copyWith(anchor: anchor)) as Self;

  /// Called when a hand or controller grabs this node, or a child with no
  /// handler of its own, in a spatial session.
  Self onGrab(VoidCallback handler) =>
      _copy(_props.copyWith(onGrab: handler)) as Self;

  /// Called when a grab on this node is released, in a spatial session.
  Self onRelease(VoidCallback handler) =>
      _copy(_props.copyWith(onRelease: handler)) as Self;
}

/// A group: a transform its children share.
class DVNode extends DVSceneNode with DVSceneNodeModifiers<DVNode> {
  DVNode({List<DVSceneNode> children = const <DVSceneNode>[]})
      : super._(const _Props(), children);

  DVNode._with(_Props props, List<DVSceneNode> children) : super._(props, children);

  @override
  String get kindName => 'node';

  @override
  DVNode _copy(_Props props) => DVNode._with(props, children);

  @override
  DVSceneNodeData _data(String id, DVTransform transform, bool visible,
          List<DVSceneNodeData> children, String Function(DVSceneAsset) assetKey) =>
      DVSceneNodeData.group(
          id: id, transform: transform, visible: visible, children: children);
}

/// An imported model.
class DVModel3D extends DVSceneNode with DVSceneNodeModifiers<DVModel3D> {
  DVModel3D(this.asset, {List<DVSceneNode> children = const <DVSceneNode>[]})
      : super._(const _Props(), children);

  DVModel3D._with(this.asset, _Props props, List<DVSceneNode> children)
      : super._(props, children);

  final DVSceneAsset asset;

  /// Draws the model with [material] instead of its own.
  DVModel3D material(DVSceneAsset material) =>
      _copy(_props.copyWith(material: material));

  @override
  String get kindName => 'model3d';

  @override
  DVModel3D _copy(_Props props) => DVModel3D._with(asset, props, children);

  @override
  DVSceneNodeData _data(String id, DVTransform transform, bool visible,
          List<DVSceneNodeData> children, String Function(DVSceneAsset) assetKey) =>
      DVSceneNodeData.model(
        id: id,
        asset: assetKey(asset),
        material: _props.material == null ? null : assetKey(_props.material!),
        transform: transform,
        visible: visible,
        children: children,
      );
}

/// A procedural shape.
class DVMesh extends DVSceneNode with DVSceneNodeModifiers<DVMesh> {
  DVMesh._(this.primitive, _Props props, List<DVSceneNode> children)
      : super._(props, children);

  /// A box with full extents [size].
  factory DVMesh.box(DVVec3 size) =>
      DVMesh._(DVScenePrimitive.box(size), const _Props(), const <DVSceneNode>[]);

  factory DVMesh.sphere(double radius) => DVMesh._(
      DVScenePrimitive.sphere(radius), const _Props(), const <DVSceneNode>[]);

  factory DVMesh.plane(double width, double depth) => DVMesh._(
      DVScenePrimitive.plane(width, depth), const _Props(), const <DVSceneNode>[]);

  final DVScenePrimitive primitive;

  DVMesh material(DVSceneAsset material) =>
      _copy(_props.copyWith(material: material));

  @override
  String get kindName => 'mesh';

  @override
  DVMesh _copy(_Props props) => DVMesh._(primitive, props, children);

  @override
  DVSceneNodeData _data(String id, DVTransform transform, bool visible,
          List<DVSceneNodeData> children, String Function(DVSceneAsset) assetKey) =>
      DVSceneNodeData.mesh(
        id: id,
        primitive: primitive,
        material: _props.material == null ? null : assetKey(_props.material!),
        transform: transform,
        visible: visible,
        children: children,
      );
}

/// The camera a viewport draws from.
///
/// `DVSceneCamera` rather than the specification's `DVCamera`, which is
/// already the device camera at `DV.Platform.Camera`; a scene camera that
/// could also `takePhoto()` would be a lie in the other direction.
class DVSceneCamera extends DVSceneNode with DVSceneNodeModifiers<DVSceneCamera> {
  DVSceneCamera._(this.camera, _Props props) : super._(props, const <DVSceneNode>[]);

  /// Orbits [target] at [distance]; with [controls], drag turns and pinch
  /// zooms it.
  factory DVSceneCamera.orbit({
    DVVec3 target = DVVec3.zero,
    required double distance,
    bool controls = false,
    double fovYDegrees = 45,
    double near = 0.1,
    double far = 1000,
  }) =>
      DVSceneCamera._(
        DVSceneCameraData.orbit(
          target: target,
          distance: distance,
          controls: controls,
          fovYDegrees: fovYDegrees,
          near: near,
          far: far,
        ),
        const _Props(),
      );

  /// Looks down its own -Z from wherever [position] and [rotation] put it.
  factory DVSceneCamera.perspective({
    double fovYDegrees = 45,
    double near = 0.1,
    double far = 1000,
  }) =>
      DVSceneCamera._(
        DVSceneCameraData.perspective(fovYDegrees: fovYDegrees, near: near, far: far),
        const _Props(),
      );

  final DVSceneCameraData camera;

  @override
  String get kindName => 'camera';

  @override
  DVSceneCamera _copy(_Props props) => DVSceneCamera._(camera, props);

  @override
  DVSceneNodeData _data(String id, DVTransform transform, bool visible,
          List<DVSceneNodeData> children, String Function(DVSceneAsset) assetKey) =>
      DVSceneNodeData.camera(id: id, camera: camera, transform: transform);
}

/// A light.
class DVLight extends DVSceneNode with DVSceneNodeModifiers<DVLight> {
  DVLight._(this.light, _Props props) : super._(props, const <DVSceneNode>[]);

  factory DVLight.directional({
    required DVVec3 direction,
    int color = 0xFFFFFF,
    double intensity = 1,
  }) =>
      DVLight._(
        DVSceneLight.directional(direction: direction, color: color, intensity: intensity),
        const _Props(),
      );

  factory DVLight.point({int color = 0xFFFFFF, double intensity = 1, double? range}) =>
      DVLight._(
        DVSceneLight.point(color: color, intensity: intensity, range: range),
        const _Props(),
      );

  factory DVLight.spot({
    required DVVec3 direction,
    int color = 0xFFFFFF,
    double intensity = 1,
    double? range,
    double innerConeDegrees = 0,
    double outerConeDegrees = 45,
  }) =>
      DVLight._(
        DVSceneLight.spot(
          direction: direction,
          color: color,
          intensity: intensity,
          range: range,
          innerConeDegrees: innerConeDegrees,
          outerConeDegrees: outerConeDegrees,
        ),
        const _Props(),
      );

  final DVSceneLight light;

  /// This light casts shadows.
  DVLight shadows([bool cast = true]) => DVLight._(light.withShadows(cast), _props);

  @override
  String get kindName => 'light';

  @override
  DVLight _copy(_Props props) => DVLight._(light, props);

  @override
  DVSceneNodeData _data(String id, DVTransform transform, bool visible,
          List<DVSceneNodeData> children, String Function(DVSceneAsset) assetKey) =>
      DVSceneNodeData.light(id: id, light: light, transform: transform, visible: visible);
}

/// The image-based lighting a scene is lit by.
class DVEnvironment {
  const DVEnvironment._(this.asset, [this.isPassthrough = false]);

  /// An environment map.
  const DVEnvironment.asset(DVSceneAsset this.asset) : isPassthrough = false;

  /// The procedural studio environment, needing no asset.
  static const DVEnvironment studio = DVEnvironment._(null);

  /// The real world through a headset's cameras, lit from an environment
  /// probe where one is available. Presented flat, the studio environment is
  /// used and `DV-XR-001` says so.
  static const DVEnvironment passthrough = DVEnvironment._(null, true);

  final DVSceneAsset? asset;
  final bool isPassthrough;
}

/// What a [DVScene] resolves to on one build.
final class DVSceneResolved {
  const DVSceneResolved._(
    this.document,
    this.tapHandlers,
    this.cameraNodeId, {
    this.grabHandlers = const <String, VoidCallback>{},
    this.releaseHandlers = const <String, VoidCallback>{},
  });

  final DV3DSceneDocument document;

  /// Tap handlers by node id.
  final Map<String, VoidCallback> tapHandlers;

  /// Grab handlers by node id, which a spatial session delivers.
  final Map<String, VoidCallback> grabHandlers;

  /// Release handlers by node id, which a spatial session delivers.
  final Map<String, VoidCallback> releaseHandlers;

  /// The first camera node, in document order.
  final String? cameraNodeId;
}

/// The 3D content of a `DVBox.scene`.
class DVScene {
  const DVScene({
    this.nodes = const <DVSceneNode>[],
    this.environment = DVEnvironment.studio,
    this.poster,
    this.label,
    this.aspectRatio = 16 / 9,
  });

  final List<DVSceneNode> nodes;
  final DVEnvironment environment;

  /// The still shown wherever the scene cannot render.
  final DVImage? poster;

  /// What assistive technology announces for the viewport.
  final String? label;

  /// The viewport's shape when its parent does not bound its height.
  final double aspectRatio;

  /// Resolves every node, reading signals, into a document.
  DVSceneResolved resolve() {
    final Map<String, DVSceneAsset> assets = <String, DVSceneAsset>{};
    String assetKey(DVSceneAsset asset) {
      final String base = '${asset.kind.name}:${asset.reference}';
      String key = base;
      for (int n = 2; assets.containsKey(key) && assets[key] != asset; n++) {
        key = '$base#$n';
      }
      assets[key] = asset;
      return key;
    }

    final Map<String, VoidCallback> handlers = <String, VoidCallback>{};
    final Map<String, VoidCallback> grabs = <String, VoidCallback>{};
    final Map<String, VoidCallback> releases = <String, VoidCallback>{};
    String? cameraId;
    List<DVSceneNodeData> build(List<DVSceneNode> nodes, String? parent) =>
        <DVSceneNodeData>[
          for (int i = 0; i < nodes.length; i++)
            (() {
              final DVSceneNode node = nodes[i];
              final String id = node.explicitId ??
                  (parent == null
                      ? '${node.kindName}#$i'
                      : '$parent/${node.kindName}#$i');
              if (node._props.onTap != null) handlers[id] = node._props.onTap!;
              if (node._props.onGrab != null) grabs[id] = node._props.onGrab!;
              if (node._props.onRelease != null) releases[id] = node._props.onRelease!;
              if (node is DVSceneCamera) cameraId ??= id;
              final Object? visible = _read(node._props.visible);
              final DVSceneNodeData data = node._data(
                id,
                node._transform(),
                (visible as bool?) ?? true,
                build(node.children, id),
                assetKey,
              );
              final DVAnchor? anchor = node._props.anchor;
              return anchor == null ? data : data.copyWith(anchor: anchor);
            })(),
        ];

    final List<DVSceneNodeData> data = build(nodes, null);
    final DVSceneAsset? environmentAsset = environment.asset;
    return DVSceneResolved._(
      DV3DSceneDocument(
        id: 'dvbox.scene',
        environment: environment.isPassthrough
            ? DV3DSceneDocument.passthroughEnvironment
            : environmentAsset == null
                ? DV3DSceneDocument.studioEnvironment
                : assetKey(environmentAsset),
        poster: poster,
        assets: assets,
        nodes: data,
      ),
      handlers,
      cameraId,
      grabHandlers: grabs,
      releaseHandlers: releases,
    );
  }
}
