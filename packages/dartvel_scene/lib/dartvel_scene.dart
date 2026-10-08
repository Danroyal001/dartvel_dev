/// The 3D renderer behind `DVBox.scene`, on Flutter Scene.
///
/// Call [DVFlutterScene.install] once at startup (the generated runtime does
/// it for a project with `dartvel.scene3d.enabled: true`). Every scene after
/// that renders through Flutter GPU, or the WebGL2 backend in a browser,
/// instead of showing its poster.
library dartvel_scene;

export 'src/flutter_scene_renderer.dart';
export 'src/scene_material.dart';
