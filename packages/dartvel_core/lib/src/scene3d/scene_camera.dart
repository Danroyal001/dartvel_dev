/// Cameras: where a scene is seen from, and the conversions a tap needs.
library dartvel.scene3d.camera;

import 'dart:math' as math;

import 'scene_document.dart';
import 'scene_math.dart';

/// A perspective camera, with the orbit it is controlled by.
///
/// Screen coordinates are logical pixels with the origin at the top left and
/// y growing downward, the way Flutter lays out, so a tap's local position
/// goes straight into [rayAt].
final class DVSceneView {
  DVSceneView({
    required this.eye,
    required this.target,
    this.up = DVVec3.up,
    this.fovYDegrees = 45,
    this.near = 0.1,
    this.far = 1000,
  })  : distance = (eye - target).length,
        yaw = math.atan2(eye.x - target.x, eye.z - target.z),
        pitch = (eye - target).length == 0
            ? 0
            : math.asin(((eye.y - target.y) / (eye - target).length).clamp(-1, 1));

  /// A camera [distance] from [target], turned [yaw] radians about the up
  /// axis and raised [pitch] radians above the horizon. Yaw 0 and pitch 0
  /// look down -Z.
  factory DVSceneView.orbit({
    DVVec3 target = DVVec3.zero,
    required double distance,
    double yaw = 0,
    double pitch = 0,
    double fovYDegrees = 45,
    double near = 0.1,
    double far = 1000,
  }) {
    final double p = pitch.clamp(-maxPitch, maxPitch);
    final double d = math.max(distance, near * 2);
    return DVSceneView._(
      eye: target +
          DVVec3(
            d * math.cos(p) * math.sin(yaw),
            d * math.sin(p),
            d * math.cos(p) * math.cos(yaw),
          ),
      target: target,
      yaw: yaw,
      pitch: p,
      distance: d,
      fovYDegrees: fovYDegrees,
      near: near,
      far: far,
    );
  }

  /// The view a document camera describes: its orbit when it has one,
  /// otherwise looking down the node's -Z from wherever [world] puts it.
  factory DVSceneView.fromCamera(DVSceneCameraData camera, {DVMat4? world}) {
    if (camera.isOrbit) {
      return DVSceneView.orbit(
        target: camera.orbitTarget!,
        distance: camera.orbitDistance!,
        fovYDegrees: camera.fovYDegrees,
        near: camera.near,
        far: camera.far,
      );
    }
    final DVMat4 m = world ?? DVMat4.identity();
    return DVSceneView(
      eye: m.transformPoint(DVVec3.zero),
      target: m.transformPoint(const DVVec3(0, 0, -1)),
      up: m.transformDirection(DVVec3.up).normalized(),
      fovYDegrees: camera.fovYDegrees,
      near: camera.near,
      far: camera.far,
    );
  }

  DVSceneView._({
    required this.eye,
    required this.target,
    required this.yaw,
    required this.pitch,
    required this.distance,
    required this.fovYDegrees,
    required this.near,
    required this.far,
  }) : up = DVVec3.up;

  /// How close to straight up or down an orbit may turn. Short of the pole,
  /// because at it the up vector and the view direction coincide and the
  /// view has no defined right.
  static const double maxPitch = math.pi / 2 - 0.01;

  final DVVec3 eye;
  final DVVec3 target;
  final DVVec3 up;
  final double fovYDegrees;
  final double near;
  final double far;
  final double yaw;
  final double pitch;
  final double distance;

  DVMat4 get view => DVMat4.lookAt(eye, target, up);

  DVMat4 projection(double aspect) =>
      DVMat4.perspective(fovYDegrees * math.pi / 180, aspect, near, far);

  /// This orbit turned by [yaw] and [pitch] radians and moved [zoom] times
  /// closer, clamped so it never passes the pole or its near plane.
  DVSceneView orbitBy({double yaw = 0, double pitch = 0, double zoom = 1}) =>
      DVSceneView.orbit(
        target: target,
        distance: zoom <= 0 ? distance : distance / zoom,
        yaw: this.yaw + yaw,
        pitch: this.pitch + pitch,
        fovYDegrees: fovYDegrees,
        near: near,
        far: far,
      );

  /// The ray from the eye through pixel ([x], [y]) of a [width] x [height]
  /// viewport.
  DVRay rayAt(double x, double y, double width, double height) {
    final DVMat4? inverse = (projection(width / height) * view).inverse();
    if (inverse == null) {
      throw StateError('This camera has no inverse view-projection.');
    }
    final DVVec3 onNear = inverse.transformPoint(
        DVVec3(2 * x / width - 1, 1 - 2 * y / height, -1));
    return DVRay(eye, (onNear - eye).normalized());
  }

  /// Where [point] is drawn in a [width] x [height] viewport, as (x, y,
  /// depth in -1..1), or null when it is behind the camera -- projecting
  /// such a point anyway mirrors it onto the screen.
  DVVec3? project(DVVec3 point, double width, double height) {
    final DVVec3 inView = view.transformPoint(point);
    if (inView.z >= 0) return null;
    final DVVec3 ndc = projection(width / height).transformPoint(inView);
    return DVVec3(
      (ndc.x + 1) / 2 * width,
      (1 - ndc.y) / 2 * height,
      ndc.z,
    );
  }

  @override
  String toString() => 'DVSceneView(eye: $eye, target: $target)';
}
