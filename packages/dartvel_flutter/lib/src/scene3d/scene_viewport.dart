/// `DVBox.scene`: the viewport a scene renders in.
///
/// The box owns size, modifiers, gestures and semantics; the scene owns the
/// 3D content. On every build the scene's nodes are resolved into a document.
/// When only transforms and visibility changed -- the common case, a signal
/// moving a node -- they are written into the running scene graph and the
/// next frame draws them; nothing reloads. When the structure changed, the
/// runtime loads what is new and keeps drawing the old scene until it can
/// swap. Where the scene cannot render at all, the box shows the poster,
/// labelled with why, and the runtime has already reported it.
library dartvel_flutter.scene3d.viewport;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';
import '../media/image_view.dart';

/// A renderer that draws onto a Flutter canvas: the shape a Flutter GPU
/// adapter takes, rendering to a texture and drawing it here.
abstract interface class DVSceneCanvasRenderer implements DVSceneRenderer {
  void paint(Canvas canvas, Size size, DVSceneFrame frame);
}

/// Reads what a viewport is doing: whether it renders, and if not, why.
class DVSceneController extends ChangeNotifier {
  DV3DDegradation _degradation = DV3DDegradation.none;
  bool _isRendering = false;
  List<String> _failedAssets = const <String>[];
  DVSceneRuntime? _runtime;
  DVSceneView? _view;

  /// Why the poster is shown, or [DV3DDegradation.none].
  DV3DDegradation get degradation => _degradation;

  /// Whether frames are being drawn. False while assets load.
  bool get isRendering => _isRendering;

  /// Asset keys that did not load.
  List<String> get failedAssets => _failedAssets;

  DVSceneRuntime? get runtime => _runtime;

  /// The camera frames are drawn from, including any orbit the user dragged.
  DVSceneView? get view => _view;

  void _set(DVSceneRuntime runtime, DVSceneView? view, {bool notify = true}) {
    final bool changed = !identical(runtime, _runtime) ||
        runtime.degradation != _degradation ||
        runtime.isRendering != _isRendering ||
        !listEquals(runtime.failedAssets, _failedAssets) ||
        view != _view;
    _runtime = runtime;
    _view = view;
    _degradation = runtime.degradation;
    _isRendering = runtime.isRendering;
    _failedAssets = runtime.failedAssets;
    if (notify && changed) notifyListeners();
  }
}

/// `DVBox.scene(...)`.
///
/// A callable rather than a constructor so the box keeps its one layout
/// vocabulary and `DVBox.scene` can grow siblings, such as the specification's
/// `DVBox.scene.game(...)`, without a second widget type.
class DVSceneBoxFactory {
  const DVSceneBoxFactory();

  DVBox<Object?> call(
    DVScene scene, {
    DVSceneController? controller,
    DVModifier? modifier,
  }) =>
      DVBox<Object?>(DVSceneViewport(scene: scene, controller: controller), modifier);
}

/// The widget inside `DVBox.scene`.
class DVSceneViewport extends StatefulWidget {
  const DVSceneViewport({super.key, required this.scene, this.controller});

  final DVScene scene;
  final DVSceneController? controller;

  @override
  State<DVSceneViewport> createState() => _DVSceneViewportState();
}

class _DVSceneViewportState extends State<DVSceneViewport> {
  DVSceneController? _ownController;
  DVSceneRuntime? _runtime;
  DVSceneRenderer? _renderer;
  DVSceneResolved? _resolved;
  String? _structure;
  String? _cameraSignature;
  DVSceneView? _view;
  bool _controls = false;
  double _lastScale = 1;

  DVSceneController get _controller =>
      widget.controller ?? (_ownController ??= DVSceneController());

  /// Where an asset's bytes come from when the application configured
  /// nothing for its source: the bundle, and `DV.FileStorage`. Network assets
  /// have no default, because no host is allowed until one is configured.
  static final Map<DVSceneAssetSource, DVSceneAssetFetch> _defaultFetchers =
      <DVSceneAssetSource, DVSceneAssetFetch>{
    DVSceneAssetSource.bundled: (DVSceneAsset asset) async {
      try {
        final ByteData data = await rootBundle.load(asset.reference);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } on FlutterError {
        return null;
      }
    },
    DVSceneAssetSource.stored: (DVSceneAsset asset) =>
        DV.FileStorage.get(asset.reference),
  };

  @override
  void dispose() {
    _runtime?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DVSceneResolved resolved = widget.scene.resolve();
    _resolved = resolved;
    final DVSceneRuntime runtime = _apply(resolved);
    _controller._set(runtime, _view, notify: false);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget content = runtime.isRendering
            ? _live(runtime)
            : _poster(runtime.degradation);
        return constraints.hasBoundedHeight
            ? content
            : AspectRatio(aspectRatio: widget.scene.aspectRatio, child: content);
      },
    );
  }

  DVSceneRuntime _apply(DVSceneResolved resolved) {
    final DV3DSceneDocument document = resolved.document;
    final String structure = _structureOf(document);
    DVSceneRuntime? runtime = _runtime;
    if (runtime == null) {
      _renderer = DVScene3D.createRenderer();
      runtime = _runtime = DVSceneRuntime(
        document: document,
        renderer: _renderer,
        loader: DVScene3D.createLoader(defaults: _defaultFetchers),
        enabled: DVScene3D.enabled,
      );
      _structure = structure;
      _track(runtime.start());
    } else if (structure != _structure) {
      _structure = structure;
      _track(runtime.update(document));
    } else {
      final DVSceneGraph graph = runtime.graph;
      for (final DVSceneNodeData node in document.walk()) {
        if (!graph.contains(node.id)) continue;
        graph.setTransform(node.id, node.transform);
        graph.setVisible(node.id, node.visible);
      }
    }
    _updateView(resolved, runtime);
    return runtime;
  }

  void _track(Future<DV3DDegradation> work) {
    unawaited(work.then(
      (DV3DDegradation _) {
        final DVSceneRuntime? runtime = _runtime;
        if (!mounted || runtime == null) return;
        setState(() {});
        _controller._set(runtime, _view);
      },
      onError: (Object error, StackTrace stack) => FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'dartvel scene3d',
          context: ErrorDescription('while loading a DVBox.scene'),
        ),
      ),
    ));
  }

  /// The document with every transform and visibility removed: two builds
  /// with the same structure differ only in what a frame can apply directly.
  static String _structureOf(DV3DSceneDocument document) {
    Object? strip(Object? value) {
      if (value is Map) {
        return <String, Object?>{
          for (final MapEntry<Object?, Object?> e in value.entries)
            if (e.key != 'transform' && e.key != 'visible')
              e.key! as String: strip(e.value),
        };
      }
      if (value is List) return <Object?>[for (final Object? v in value) strip(v)];
      return value;
    }

    return jsonEncode(strip(document.toJson()));
  }

  void _updateView(DVSceneResolved resolved, DVSceneRuntime runtime) {
    final String? cameraId = resolved.cameraNodeId;
    final DVSceneNodeData? camera =
        cameraId == null ? null : resolved.document.find(cameraId);
    final String signature =
        camera == null ? 'default' : jsonEncode(camera.toJson());
    // An orbit the user has dragged is kept until the scene's own camera
    // changes.
    if (signature == _cameraSignature && _view != null) return;
    _cameraSignature = signature;
    if (camera == null) {
      _view = DVSceneView.orbit(distance: 3);
      _controls = false;
      return;
    }
    final DVSceneCameraData data = camera.camera!;
    _controls = data.isOrbit && data.controls;
    _view = DVSceneView.fromCamera(
      data,
      world: runtime.graph.contains(camera.id)
          ? runtime.graph.worldMatrix(camera.id)
          : camera.transform.matrix,
    );
  }

  Widget _live(DVSceneRuntime runtime) => Semantics(
        label: widget.scene.label ?? '3D scene',
        image: true,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails details) =>
                  _tap(runtime, details.localPosition, size),
              onScaleStart: _controls ? (ScaleStartDetails _) => _lastScale = 1 : null,
              onScaleUpdate: _controls ? _orbit : null,
              child: CustomPaint(
                size: size,
                painter: _DVScenePainter(runtime, _renderer, _view!),
              ),
            );
          },
        ),
      );

  void _tap(DVSceneRuntime runtime, Offset position, Size size) {
    final DVSceneResolved? resolved = _resolved;
    if (resolved == null || size.isEmpty || !runtime.isRendering) return;
    // The nearest thing under the pointer takes the tap, handler or not, so
    // a wall in front of a button blocks it; a node with no handler passes
    // it up to the nearest ancestor that has one.
    String? id = runtime
        .pickAt(_view!, position.dx, position.dy, size.width, size.height)
        ?.nodeId;
    while (id != null) {
      final VoidCallback? handler = resolved.tapHandlers[id];
      if (handler != null) {
        handler();
        return;
      }
      id = runtime.graph.parentOf(id);
    }
  }

  void _orbit(ScaleUpdateDetails details) {
    final DVSceneRuntime? runtime = _runtime;
    if (runtime == null) return;
    setState(() {
      _view = _view!.orbitBy(
        yaw: -details.focalPointDelta.dx * 0.01,
        pitch: details.focalPointDelta.dy * 0.01,
        zoom: _lastScale == 0 ? 1 : details.scale / _lastScale,
      );
      _lastScale = details.scale;
    });
    _controller._set(runtime, _view);
  }

  Widget _poster(DV3DDegradation degradation) {
    final DVImage? poster = widget.scene.poster;
    final String label = widget.scene.label ?? '3D scene';
    final String state = degradation == DV3DDegradation.none
        ? 'loading'
        : 'shown as a still image (${degradation.name})';
    return Semantics(
      label: '$label, $state',
      image: true,
      child: SizedBox.expand(
        child: poster == null
            // Never a hole: with no poster, a neutral surface of the right
            // size, which the label above still describes.
            ? const ColoredBox(color: Color(0xFFE6E6EA))
            : DVImageRender(poster, fit: BoxFit.cover),
      ),
    );
  }
}

class _DVScenePainter extends CustomPainter {
  _DVScenePainter(this.runtime, this.renderer, this.view);

  final DVSceneRuntime runtime;
  final DVSceneRenderer? renderer;
  final DVSceneView view;

  @override
  void paint(Canvas canvas, Size size) {
    if (!runtime.isRendering || size.isEmpty) return;
    final DVSceneFrame frame = runtime.frame(view, size.width, size.height);
    final DVSceneRenderer? target = renderer;
    if (target is DVSceneCanvasRenderer) target.paint(canvas, size, frame);
  }

  @override
  bool shouldRepaint(_DVScenePainter oldDelegate) => true;
}
