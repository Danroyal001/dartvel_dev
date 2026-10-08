/// The `DVSceneRenderer` adapter over Flutter Scene.
///
/// The runtime in dartvel_core owns what must hold whatever draws (assets
/// verified before upload, every resource released once, draws in document
/// order, a poster with a reason). This adapter only translates: each frame's
/// draws and lights become Flutter Scene nodes, keyed by the document's node
/// ids so a node that moves is moved rather than rebuilt, and the frame's view
/// becomes a perspective camera.
library dartvel_scene.renderer;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart' show DVSceneCanvasRenderer;
import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart' as fs;
import 'package:vector_math/vector_math.dart' as vm;

import 'scene_material.dart';

/// Installs Flutter Scene as the renderer for every `DVBox.scene`.
abstract final class DVFlutterScene {
  /// Every scene created after this renders through Flutter Scene.
  static void install() => DVScene3D.configure(renderer: DVFlutterSceneRenderer.new);
}

/// What one uploaded asset became.
final class _Upload {
  _Upload.material(this.assetKey, this.material) : model = null;
  _Upload.model(this.assetKey, this.model) : material = null;

  final String assetKey;
  final DVSceneMaterialSpec? material;
  final Future<fs.Node>? model;
  fs.Node? loadedModel;
  bool released = false;
}

/// One document node as it stands in the Flutter Scene graph.
final class _Placed {
  _Placed(this.node, this.signature);

  final fs.Node node;

  /// What the node was built from; a change rebuilds it.
  final String signature;
}

/// Renders `DVBox.scene` through Flutter Scene: Flutter GPU on native
/// targets, the engine's WebGL2 backend in a browser.
///
/// A [Listenable]: it notifies when an asynchronously imported model becomes
/// ready, so the viewport paints it without waiting for another rebuild.
final class DVFlutterSceneRenderer extends ChangeNotifier implements DVSceneCanvasRenderer {
  DVFlutterSceneRenderer();

  // Made in initialize, once Flutter GPU is known to be there: constructing a
  // Scene on a target without it throws, and a missing GPU must be a poster.
  fs.Scene? _scene;

  // Dartvel's scene world is right-handed (Y up, -Z forward) and Flutter
  // Scene's is left-handed, the way its own glTF importer roots every model
  // under scale(1, 1, -1). Everything is placed under one such root, and the
  // camera is flipped to match, so +X is on the right of the screen in both.
  final fs.Node _root = fs.Node(name: 'dartvel', localTransform: vm.Matrix4.diagonal3Values(1, 1, -1));
  final Map<int, _Upload> _uploads = <int, _Upload>{};
  final Map<String, _Placed> _placed = <String, _Placed>{};
  final Map<String, _Placed> _lights = <String, _Placed>{};
  int _nextHandle = 1;
  bool _disposed = false;
  fs.PerspectiveCamera? _camera;

  /// Why initialization failed, when it did.
  Object? initializationError;

  /// Resources uploaded and not yet released.
  int get liveResources => _uploads.length;

  @override
  String get name => 'flutter_scene';

  @override
  Future<DV3DDegradation> initialize() async {
    try {
      await fs.Scene.initializeStaticResources();
      _scene = fs.Scene()..add(_root);
      return .none;
    } catch (error) {
      // No Flutter GPU on this embedder (or it is switched off): the poster,
      // with a reason, never a hole.
      initializationError = error;
      return .gpuInitFailed;
    }
  }

  @override
  DVSceneResource upload(String assetKey, DVSceneAsset asset, DVSceneAssetState loaded) {
    final int handle = _nextHandle++;
    final Uint8List bytes = loaded.bytes ?? Uint8List(0);
    switch (asset.kind) {
      case .material:
        _uploads[handle] = _Upload.material(assetKey, DVSceneMaterialSpec.fromBytes(bytes));
      case .model:
        final _Upload upload = _Upload.model(assetKey, fs.Node.fromGlbBytes(bytes));
        _uploads[handle] = upload;
        unawaited(upload.model!.then((fs.Node node) {
          if (upload.released || _disposed) return;
          upload.loadedModel = node;
          notifyListeners();
        }, onError: (Object error, StackTrace stack) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'dartvel_scene',
            context: ErrorDescription('while importing the 3D model "$assetKey"'),
          ));
        }));
      case .environment:
      case .texture:
        // Carried, not yet drawn: the studio environment lights every scene.
        _uploads[handle] = _Upload.material(assetKey, null);
    }
    return DVSceneResource(handle, assetKey);
  }

  @override
  void release(DVSceneResource resource) {
    final _Upload? upload = _uploads.remove(resource.handle);
    if (upload == null) return;
    upload.released = true;
  }

  @override
  void render(DVSceneFrame frame) {
    final fs.Scene? scene = _scene;
    if (_disposed || scene == null) return;
    final Set<String> seen = <String>{};
    for (final DVSceneDraw draw in frame.draws) {
      seen.add(draw.nodeId);
      final _Upload? material = draw.material == null ? null : _uploads[draw.material!.handle];
      final _Upload? model = draw.resource == null ? null : _uploads[draw.resource!.handle];
      final String signature = _drawSignature(draw, material, model);
      _Placed? placed = _placed[draw.nodeId];
      if (placed == null || placed.signature != signature) {
        if (placed != null) _root.remove(placed.node);
        final fs.Node? node = _buildDraw(draw, material?.material, model);
        if (node == null) {
          _placed.remove(draw.nodeId);
          continue;
        }
        placed = _Placed(node, signature);
        _placed[draw.nodeId] = placed;
        _root.add(node);
      }
      placed.node.localTransform = _matrix(draw.world);
    }
    for (final String gone in _placed.keys.where((String id) => !seen.contains(id)).toList()) {
      _root.remove(_placed.remove(gone)!.node);
    }
    _syncLights(frame.lights);
    final DVSceneView view = frame.view;
    _camera = fs.PerspectiveCamera(
      fovRadiansY: view.fovYDegrees * vm.degrees2Radians,
      position: _flipped(view.eye),
      target: _flipped(view.target),
      up: _flipped(view.up),
      fovNear: view.near,
      fovFar: view.far,
    );
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size, DVSceneFrame frame) {
    final fs.PerspectiveCamera? camera = _camera;
    final fs.Scene? scene = _scene;
    if (_disposed || scene == null || camera == null || size.isEmpty) return;
    scene.render(camera, canvas, viewport: ui.Offset.zero & size);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _scene?.removeAll();
    _root.removeAll();
    _placed.clear();
    _lights.clear();
    for (final _Upload upload in _uploads.values) {
      upload.released = true;
    }
    _uploads.clear();
    super.dispose();
  }

  String _drawSignature(DVSceneDraw draw, _Upload? material, _Upload? model) {
    final DVScenePrimitive? primitive = draw.primitive;
    return <Object?>[
      primitive?.shape.name,
      primitive?.size.x,
      primitive?.size.y,
      primitive?.size.z,
      draw.material?.handle,
      draw.resource?.handle,
      // A model that finished importing since the last frame is drawn now.
      model?.loadedModel == null ? 'pending' : 'ready',
      material?.material?.hashCode,
    ].join('|');
  }

  fs.Node? _buildDraw(DVSceneDraw draw, DVSceneMaterialSpec? material, _Upload? model) {
    if (model != null) {
      final fs.Node? imported = model.loadedModel;
      if (imported == null) return null;
      // One import can be drawn by several nodes; each gets its own copy.
      return fs.Node(name: draw.nodeId)..add(imported.clone());
    }
    final DVScenePrimitive? primitive = draw.primitive;
    if (primitive == null) return null;
    final DVVec3 size = primitive.size;
    final fs.Geometry geometry = switch (primitive.shape) {
      .box => fs.CuboidGeometry(vm.Vector3(size.x, size.y, size.z)),
      .sphere => fs.SphereGeometry(radius: size.x),
      .plane => fs.PlaneGeometry(width: size.x, depth: size.z),
    };
    return fs.Node(name: draw.nodeId, mesh: fs.Mesh(geometry, _material(material ?? const DVSceneMaterialSpec())));
  }

  static fs.PhysicallyBasedMaterial _material(DVSceneMaterialSpec spec) {
    final List<double> base = DVSceneMaterialSpec.channels(spec.baseColor);
    final List<double> glow = DVSceneMaterialSpec.channels(spec.emissive);
    return fs.PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(base[0], base[1], base[2], spec.opacity)
      ..metallicFactor = spec.metallic
      ..roughnessFactor = spec.roughness
      ..emissiveFactor = vm.Vector4(glow[0], glow[1], glow[2], 1);
  }

  void _syncLights(List<DVSceneLightDraw> lights) {
    final Set<String> seen = <String>{};
    for (final DVSceneLightDraw draw in lights) {
      seen.add(draw.nodeId);
      final DVSceneLight light = draw.light;
      final String signature = <Object?>[
        light.type.name,
        light.color,
        light.intensity,
        light.range,
        light.innerConeDegrees,
        light.outerConeDegrees,
        light.castShadows,
        light.direction?.x,
        light.direction?.y,
        light.direction?.z,
      ].join('|');
      _Placed? placed = _lights[draw.nodeId];
      if (placed == null || placed.signature != signature) {
        if (placed != null) _root.remove(placed.node);
        placed = _Placed(_buildLight(draw.nodeId, light), signature);
        _lights[draw.nodeId] = placed;
        _root.add(placed.node);
      }
      placed.node.localTransform = _matrix(draw.world);
    }
    for (final String gone in _lights.keys.where((String id) => !seen.contains(id)).toList()) {
      _root.remove(_lights.remove(gone)!.node);
    }
  }

  static fs.Node _buildLight(String id, DVSceneLight light) {
    final List<double> rgb = DVSceneMaterialSpec.channels(light.color);
    final vm.Vector3 color = vm.Vector3(rgb[0], rgb[1], rgb[2]);
    final vm.Vector3 direction = light.direction == null ? vm.Vector3(0, -1, 0) : _vec(light.direction!);
    final fs.Node node = fs.Node(name: id);
    switch (light.type) {
      case .directional:
        node.addComponent(fs.DirectionalLightComponent.aimed(
          fs.DirectionalLight(color: color, intensity: light.intensity, castsShadow: light.castShadows),
          direction,
        ));
      case .point:
        node.addComponent(fs.PointLightComponent(fs.PointLight(
          color: color,
          intensity: light.intensity,
          range: light.range ?? 0,
          castsShadow: light.castShadows,
        )));
      case .spot:
        node.addComponent(fs.SpotLightComponent(fs.SpotLight(
          color: color,
          intensity: light.intensity,
          range: light.range ?? 0,
          direction: direction,
          innerConeAngle: (light.innerConeDegrees ?? 0) * vm.degrees2Radians,
          outerConeAngle: (light.outerConeDegrees ?? 45) * vm.degrees2Radians,
          castsShadow: light.castShadows,
        )));
    }
    return node;
  }

  static vm.Vector3 _vec(DVVec3 value) => vm.Vector3(value.x, value.y, value.z);

  /// A point or direction in Dartvel's world, in Flutter Scene's.
  static vm.Vector3 _flipped(DVVec3 value) => vm.Vector3(value.x, value.y, -value.z);

  static vm.Matrix4 _matrix(DVMat4 value) => vm.Matrix4.fromList(value.storage.toList());
}
