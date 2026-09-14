/// Where scenes get their renderer and their asset sources.
library dartvel.scene3d.config;

import 'scene_assets.dart';
import 'scene_document.dart';
import 'scene_renderer.dart';

/// The application's 3D configuration.
///
/// No renderer is configured by default, and that is the honest default:
/// until a Flutter GPU adapter is registered for the target, every scene
/// presents its poster and reports `DV-3D-001` rather than pretending to
/// draw.
abstract final class DVScene3D {
  static bool _enabled = true;
  static DVSceneRenderer? Function() _renderer = _noRenderer;
  static DVSceneAssetPolicy _policy = const DVSceneAssetPolicy();
  static Map<DVSceneAssetSource, DVSceneAssetFetch> _fetchers =
      const <DVSceneAssetSource, DVSceneAssetFetch>{};

  static DVSceneRenderer? _noRenderer() => null;

  /// `dartvel.scene3d.enabled`.
  static bool get enabled => _enabled;

  static DVSceneAssetPolicy get policy => _policy;

  /// Fetchers configured by the application, by source. A platform layer
  /// adds its own defaults beneath these (bundle and file storage in
  /// dartvel_flutter).
  static Map<DVSceneAssetSource, DVSceneAssetFetch> get fetchers =>
      Map<DVSceneAssetSource, DVSceneAssetFetch>.unmodifiable(_fetchers);

  /// Replaces the parts given.
  static void configure({
    bool? enabled,
    DVSceneRenderer? Function()? renderer,
    DVSceneAssetPolicy? policy,
    Map<DVSceneAssetSource, DVSceneAssetFetch>? fetchers,
  }) {
    if (enabled != null) _enabled = enabled;
    if (renderer != null) _renderer = renderer;
    if (policy != null) _policy = policy;
    if (fetchers != null) {
      _fetchers = Map<DVSceneAssetSource, DVSceneAssetFetch>.of(fetchers);
    }
  }

  /// Back to no renderer, the default policy, no fetchers, enabled.
  static void reset() {
    _enabled = true;
    _renderer = _noRenderer;
    _policy = const DVSceneAssetPolicy();
    _fetchers = const <DVSceneAssetSource, DVSceneAssetFetch>{};
  }

  /// A renderer for one scene, or null when this target has none. Each scene
  /// owns and disposes the renderer it is given.
  static DVSceneRenderer? createRenderer() => _renderer();

  /// A loader under the configured policy, with [defaults] beneath the
  /// configured fetchers.
  static DVSceneAssetLoader createLoader({
    Map<DVSceneAssetSource, DVSceneAssetFetch> defaults =
        const <DVSceneAssetSource, DVSceneAssetFetch>{},
  }) =>
      DVSceneAssetLoader(
        policy: _policy,
        fetchers: <DVSceneAssetSource, DVSceneAssetFetch>{
          ...defaults,
          ..._fetchers,
        },
      );
}

/// The headless backend `DV.Test.fake3D()` installs.
final class DVSceneFake {
  DVSceneFake._(this.initialization);

  final DV3DDegradation initialization;

  /// Every renderer handed out, oldest first.
  final List<DVSceneRecordingRenderer> renderers = <DVSceneRecordingRenderer>[];

  DVSceneRecordingRenderer? get last => renderers.isEmpty ? null : renderers.last;

  /// Installs a fake as the renderer every new scene gets.
  static DVSceneFake install({
    DV3DDegradation initialization = DV3DDegradation.none,
  }) {
    final DVSceneFake fake = DVSceneFake._(initialization);
    DVScene3D.configure(renderer: () {
      final DVSceneRecordingRenderer renderer =
          DVSceneRecordingRenderer(initialization: fake.initialization);
      fake.renderers.add(renderer);
      return renderer;
    });
    return fake;
  }
}
