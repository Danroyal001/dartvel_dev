/// 3D Scenes: the platform-independent scene runtime.
///
/// Documents, the scene graph, cameras, picking, asset references and the
/// renderer adapter contract. Nothing here depends on Flutter or on a GPU, so
/// the CLI, the server and a headless test read and check scenes with the
/// same code the application renders them with.
library dartvel.scene3d;

export 'gltf.dart';
export 'scene_assets.dart';
export 'scene_camera.dart';
export 'scene_config.dart';
export 'scene_content.dart';
export 'scene_document.dart';
export 'scene_graph.dart';
export 'scene_math.dart';
export 'scene_model_field.dart';
export 'scene_renderer.dart';
