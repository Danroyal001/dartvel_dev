/// The viewer a generated `product.viewer3D()` renders.
library dartvel_flutter.scene3d.model_viewer;

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// An orbit viewer for one 3D asset: `DVBox.scene` with the model, a camera
/// the user can turn, a key light and the studio environment.
///
/// An application component like `User.Table()`: composed from the same
/// primitives an application uses, and replaceable by writing the
/// `DVBox.scene` directly.
class DVModel3DViewer extends StatelessWidget {
  const DVModel3DViewer(
    this.asset, {
    super.key,
    this.distance = 2.4,
    this.label,
    this.aspectRatio = 16 / 9,
    this.controller,
  });

  /// The field's value. Null renders nothing: an empty field is not a
  /// viewport with nothing in it.
  final DVSceneAsset? asset;

  /// How far the camera starts from the model, in metres.
  final double distance;
  final String? label;
  final double aspectRatio;
  final DVSceneController? controller;

  @override
  Widget build(BuildContext context) {
    final DVSceneAsset? value = asset;
    if (value == null) return const SizedBox.shrink();
    return DVBox.scene(
      DVScene(
        label: label,
        poster: value.poster,
        aspectRatio: aspectRatio,
        nodes: <DVSceneNode>[
          DVModel3D(value).id('model'),
          DVSceneCamera.orbit(distance: distance, controls: true),
          DVLight.directional(direction: const DVVec3(-1, -2, -1)).shadows(),
        ],
      ),
      controller: controller,
    );
  }
}
