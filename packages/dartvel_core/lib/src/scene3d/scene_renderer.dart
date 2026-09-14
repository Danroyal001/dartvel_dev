/// The renderer adapter contract, a recording reference implementation, and
/// the runtime that sits between a scene document and a renderer.
///
/// The renderer is an adapter because Dartvel does not build one: the pinned
/// engine's Flutter GPU renders, behind this interface, where the target has
/// it. What the runtime owns is everything that must be true whichever
/// renderer draws -- a scene with a missing asset is never drawn, every
/// uploaded resource is released exactly once, the draw list is in document
/// order, and a poster is never shown without a report saying why.
library dartvel.scene3d.renderer;

import 'dart:async';

import '../observability/observability.dart';
import 'scene_assets.dart';
import 'scene_camera.dart';
import 'scene_document.dart';
import 'scene_graph.dart';
import 'scene_math.dart';

/// Why a viewport shows its poster rather than the scene.
enum DV3DDegradation {
  none,

  /// The target has no 3D renderer (no Flutter GPU on the embedder, a
  /// watch, a terminal).
  unsupportedTarget,

  /// `scene3d` is disabled in configuration.
  disabledByConfig,

  /// The renderer is there and could not start.
  gpuInitFailed,

  /// An asset the scene uses did not load.
  assetMissing,
}

/// A renderer-side resource made from one asset.
final class DVSceneResource {
  const DVSceneResource(this.handle, this.assetKey);

  final int handle;
  final String assetKey;

  @override
  bool operator ==(Object other) =>
      other is DVSceneResource && other.handle == handle;

  @override
  int get hashCode => handle.hashCode;

  @override
  String toString() => 'DVSceneResource($handle, $assetKey)';
}

/// One thing to draw.
final class DVSceneDraw {
  const DVSceneDraw({
    required this.nodeId,
    required this.world,
    this.resource,
    this.primitive,
    this.material,
  });

  final String nodeId;
  final DVMat4 world;

  /// The model's resource, for a model node.
  final DVSceneResource? resource;

  /// The shape, for a mesh node.
  final DVScenePrimitive? primitive;
  final DVSceneResource? material;
}

/// One light in a frame.
final class DVSceneLightDraw {
  const DVSceneLightDraw({
    required this.nodeId,
    required this.light,
    required this.world,
  });

  final String nodeId;
  final DVSceneLight light;
  final DVMat4 world;
}

/// Everything a renderer needs to draw one frame.
final class DVSceneFrame {
  const DVSceneFrame({
    required this.view,
    required this.width,
    required this.height,
    this.draws = const <DVSceneDraw>[],
    this.lights = const <DVSceneLightDraw>[],
    this.environment,
    this.mirrored = false,
  });

  final DVSceneView view;
  final double width;
  final double height;

  /// In document order.
  final List<DVSceneDraw> draws;
  final List<DVSceneLightDraw> lights;
  final String? environment;

  /// Whether the scene's basis mirrors, so front faces wind the other way.
  final bool mirrored;
}

/// A 3D renderer.
abstract interface class DVSceneRenderer {
  /// For reports, e.g. `flutter_gpu`.
  String get name;

  /// Starts the renderer. [DV3DDegradation.none] when it can draw; a renderer
  /// that throws is treated as [DV3DDegradation.gpuInitFailed].
  FutureOr<DV3DDegradation> initialize();

  /// Makes a resource from a loaded asset.
  DVSceneResource upload(String assetKey, DVSceneAsset asset, DVSceneAssetState loaded);

  /// Frees [resource]. Called exactly once per upload.
  void release(DVSceneResource resource);

  void render(DVSceneFrame frame);

  /// Called once, after every resource has been released.
  void dispose();
}

/// A headless renderer that records what it was asked to do.
///
/// The reference implementation of [DVSceneRenderer], and what scene logic is
/// tested against without a GPU. Stricter than a real driver on purpose: a
/// double release, a draw using a released resource, or any call after
/// dispose throws, so a lifetime bug fails a test rather than corrupting a
/// frame on somebody's device.
final class DVSceneRecordingRenderer implements DVSceneRenderer {
  DVSceneRecordingRenderer({
    this.initialization = DV3DDegradation.none,
    this.initializationError,
  });

  final DV3DDegradation initialization;
  final Object? initializationError;

  final List<DVSceneResource> uploads = <DVSceneResource>[];
  final List<DVSceneResource> releases = <DVSceneResource>[];
  final List<DVSceneResource> live = <DVSceneResource>[];
  final List<DVSceneFrame> frames = <DVSceneFrame>[];
  bool initialized = false;
  bool disposed = false;
  int _next = 1;

  @override
  String get name => 'recording';

  void _alive() {
    if (disposed) throw StateError('The renderer has been disposed.');
  }

  @override
  DV3DDegradation initialize() {
    _alive();
    initialized = true;
    final Object? error = initializationError;
    if (error != null) throw error;
    return initialization;
  }

  @override
  DVSceneResource upload(String assetKey, DVSceneAsset asset, DVSceneAssetState loaded) {
    _alive();
    if (!loaded.isReady) {
      throw StateError("'$assetKey' is not ready; a renderer only takes verified bytes.");
    }
    final DVSceneResource resource = DVSceneResource(_next++, assetKey);
    uploads.add(resource);
    live.add(resource);
    return resource;
  }

  @override
  void release(DVSceneResource resource) {
    _alive();
    if (!live.remove(resource)) {
      throw StateError('$resource was released twice or never uploaded.');
    }
    releases.add(resource);
  }

  @override
  void render(DVSceneFrame frame) {
    _alive();
    for (final DVSceneDraw draw in frame.draws) {
      for (final DVSceneResource? r in <DVSceneResource?>[draw.resource, draw.material]) {
        if (r != null && !live.contains(r)) {
          throw StateError('${draw.nodeId} draws $r after it was released.');
        }
      }
    }
    frames.add(frame);
  }

  @override
  void dispose() {
    _alive();
    disposed = true;
  }
}

/// A scene document, loaded and bound to a renderer.
final class DVSceneRuntime {
  DVSceneRuntime({
    required DV3DSceneDocument document,
    required DVSceneRenderer? renderer,
    required DVSceneAssetLoader loader,
    bool enabled = true,
  })  : _document = document,
        _graph = DVSceneGraph(document),
        _renderer = renderer,
        _loader = loader,
        _enabled = enabled;

  DV3DSceneDocument _document;
  DVSceneGraph _graph;
  final DVSceneRenderer? _renderer;
  final DVSceneAssetLoader _loader;
  final bool _enabled;

  final Map<String, DVSceneResource> _resources = <String, DVSceneResource>{};
  final Map<String, DVSceneAsset> _uploaded = <String, DVSceneAsset>{};
  DV3DDegradation _degradation = DV3DDegradation.none;
  DV3DDegradation? _targetCause;
  List<String> _failed = const <String>[];
  bool _initialized = false;
  bool _ready = false;
  bool _disposed = false;
  int _generation = 0;

  static final Set<String> _reported = <String>{};

  /// Forgets which degradations were reported this boot. For tests.
  static void debugResetReports() => _reported.clear();

  DV3DSceneDocument get document => _document;
  DVSceneGraph get graph => _graph;
  DV3DDegradation get degradation => _degradation;

  /// Asset keys that did not load, sorted.
  List<String> get failedAssets => List<String>.unmodifiable(_failed);

  int get liveResources => _resources.length;

  /// Whether a frame can be drawn.
  bool get isRendering => _ready && !_disposed && _degradation == DV3DDegradation.none;

  /// Starts the renderer and loads the scene's assets.
  Future<DV3DDegradation> start() async {
    if (_disposed) return _degradation;
    if (!_enabled) return _degrade(DV3DDegradation.disabledByConfig);
    final DVSceneRenderer? renderer = _renderer;
    if (renderer == null) return _degrade(DV3DDegradation.unsupportedTarget);
    DV3DDegradation initial;
    try {
      initial = await renderer.initialize();
    } on Object catch (error) {
      _initialized = true;
      return _degrade(DV3DDegradation.gpuInitFailed, error: error);
    }
    _initialized = true;
    if (_disposed) return _degradation;
    if (initial != DV3DDegradation.none) return _degrade(initial);
    return _sync();
  }

  /// Moves to [next], keeping the resources for assets it still uses.
  Future<DV3DDegradation> update(DV3DSceneDocument next) async {
    if (_disposed) return _degradation;
    _document = next;
    _graph = DVSceneGraph(next);
    if (_targetCause != null || !_initialized) return _degradation;
    return _sync();
  }

  Future<DV3DDegradation> _sync() async {
    final int generation = ++_generation;
    final DV3DSceneDocument document = _document;
    final List<String> keys = _referencedAssets(document);
    final List<DVSceneAssetState> states = await Future.wait(<Future<DVSceneAssetState>>[
      for (final String key in keys) _loader.load(key, document.assets[key]!),
    ]);
    // Disposed, or overtaken by a newer update, while loading.
    if (_disposed || generation != _generation) return _degradation;

    final List<String> failed = <String>[
      for (int i = 0; i < keys.length; i++)
        if (!states[i].isReady) keys[i],
    ];
    _failed = failed;
    if (failed.isNotEmpty) {
      _releaseAll();
      for (int i = 0; i < keys.length; i++) {
        if (!states[i].isReady) {
          _degrade(DV3DDegradation.assetMissing,
              assetKey: keys[i], asset: document.assets[keys[i]], state: states[i]);
        }
      }
      _ready = false;
      return _degradation;
    }

    final DVSceneRenderer renderer = _renderer!;
    for (final String key in _resources.keys.toList()) {
      if (!keys.contains(key) || _uploaded[key] != document.assets[key]) {
        renderer.release(_resources.remove(key)!);
        _uploaded.remove(key);
      }
    }
    for (int i = 0; i < keys.length; i++) {
      final String key = keys[i];
      if (_resources.containsKey(key)) continue;
      _resources[key] = renderer.upload(key, document.assets[key]!, states[i]);
      _uploaded[key] = document.assets[key]!;
    }
    for (final DVSceneNodeData node in document.walk()) {
      if (node.kind == DVSceneNodeKind.model) {
        _graph.setLocalBounds(node.id, states[keys.indexOf(node.asset!)].model?.bounds);
      }
    }
    _degradation = DV3DDegradation.none;
    _ready = true;
    return _degradation;
  }

  static List<String> _referencedAssets(DV3DSceneDocument document) {
    final Set<String> keys = <String>{
      for (final DVSceneNodeData node in document.walk()) ...<String>[
        if (node.asset != null) node.asset!,
        if (node.material != null) node.material!,
      ],
      if (document.environment != null &&
          document.environment != DV3DSceneDocument.studioEnvironment)
        document.environment!,
    };
    return keys.toList()..sort();
  }

  /// Draws the scene from [view] into a [width] x [height] viewport.
  DVSceneFrame frame(DVSceneView view, double width, double height) {
    if (_disposed) throw StateError('The scene has been disposed.');
    if (!isRendering) {
      throw StateError(
          'The scene is presented as its poster (${_ready ? _degradation.name : 'not started'}); '
          'there is no frame to draw.');
    }
    final List<DVSceneDraw> draws = <DVSceneDraw>[];
    final List<DVSceneLightDraw> lights = <DVSceneLightDraw>[];
    for (final DVSceneNodeData node in _document.walk()) {
      if (!_graph.isVisibleInWorld(node.id)) continue;
      switch (node.kind) {
        case DVSceneNodeKind.model:
        case DVSceneNodeKind.mesh:
          draws.add(DVSceneDraw(
            nodeId: node.id,
            world: _graph.worldMatrix(node.id),
            resource: node.asset == null ? null : _resources[node.asset],
            primitive: node.primitive,
            material: node.material == null ? null : _resources[node.material],
          ));
        case DVSceneNodeKind.light:
          lights.add(DVSceneLightDraw(
              nodeId: node.id, light: node.light!, world: _graph.worldMatrix(node.id)));
        case DVSceneNodeKind.group:
        case DVSceneNodeKind.camera:
          break;
      }
    }
    final DVSceneFrame frame = DVSceneFrame(
      view: view,
      width: width,
      height: height,
      draws: List<DVSceneDraw>.unmodifiable(draws),
      lights: List<DVSceneLightDraw>.unmodifiable(lights),
      environment: _document.environment,
      mirrored: _graph.basisMirrors,
    );
    _renderer!.render(frame);
    return frame;
  }

  /// The node under pixel ([x], [y]), for a tap.
  DVScenePick? pickAt(
    DVSceneView view,
    double x,
    double y,
    double width,
    double height, {
    bool Function(String id)? where,
  }) =>
      _graph.pick(view.rayAt(x, y, width, height), where: where);

  /// Releases every resource once and disposes the renderer. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _releaseAll();
    final DVSceneRenderer? renderer = _renderer;
    if (renderer != null) renderer.dispose();
  }

  void _releaseAll() {
    final DVSceneRenderer? renderer = _renderer;
    if (renderer == null) return;
    for (final DVSceneResource resource in _resources.values) {
      renderer.release(resource);
    }
    _resources.clear();
    _uploaded.clear();
  }

  DV3DDegradation _degrade(
    DV3DDegradation cause, {
    Object? error,
    String? assetKey,
    DVSceneAsset? asset,
    DVSceneAssetState? state,
  }) {
    _degradation = cause;
    _ready = cause == DV3DDegradation.none;
    if (cause != DV3DDegradation.assetMissing) _targetCause = cause;
    // A target-wide cause is one fact about this boot, whatever number of
    // viewports meet it. A missing asset is a fact about that asset, and a
    // second missing asset is news.
    final String once = assetKey == null
        ? cause.name
        : '${cause.name}:$assetKey:${asset?.reference}';
    if (_reported.add(once)) {
      DVObservability.log(
        assetKey == null
            ? 'A 3D scene is presented as its poster: ${cause.name}.'
            : "A 3D scene is presented as its poster: its asset '$assetKey' did not load "
                '(${state?.failure?.name}).',
        level: DVLogLevel.info,
        code: 'DV-3D-001',
        context: <String, Object?>{
          'degradation': cause.name,
          'scene': _document.id,
          if (assetKey != null) 'asset': assetKey,
          if (asset != null) 'reference': asset.reference,
          if (state?.failure != null) 'failure': state!.failure!.name,
          if (state?.reason != null) 'reason': state!.reason,
          if (error != null) 'error': error.toString(),
        },
      );
    }
    return cause;
  }
}
