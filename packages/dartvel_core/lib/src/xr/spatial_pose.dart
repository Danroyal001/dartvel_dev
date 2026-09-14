/// Spatial poses, and the conversion from a device's convention into the
/// scene's world.
library dartvel.xr.pose;

import 'dart:math' as math;

import '../scene3d/scene_camera.dart';
import '../scene3d/scene_document.dart';
import '../scene3d/scene_graph.dart';
import '../scene3d/scene_math.dart';

/// A rigid pose in world space: right-handed, Y up, metres -- the space
/// `DVSceneGraph` computes world matrices in.
///
/// Head and hand poses are body data. [toString] never prints the numbers,
/// because a `toString` is how a value reaches a log.
final class DVSpatialPose {
  const DVSpatialPose({
    this.position = DVVec3.zero,
    this.orientation = DVQuat.identity,
  });

  static const DVSpatialPose identity = DVSpatialPose();

  final DVVec3 position;
  final DVQuat orientation;

  DVMat4 get matrix => DVMat4.compose(position, orientation, DVVec3.one);

  /// The direction the pose faces: its -Z.
  DVVec3 get forward => orientation.rotate(const DVVec3(0, 0, -1));

  DVVec3 get up => orientation.rotate(DVVec3.up);

  /// A scene camera at this pose, for drawing a frame from a head.
  DVSceneView view({double fovYDegrees = 90, double near = 0.05, double far = 1000}) =>
      DVSceneView(
        eye: position,
        target: position + forward,
        up: up,
        fovYDegrees: fovYDegrees,
        near: near,
        far: far,
      );

  @override
  bool operator ==(Object other) =>
      other is DVSpatialPose &&
      other.position == position &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(position, orientation);

  @override
  String toString() => 'DVSpatialPose(<redacted>)';
}

/// The coordinate convention a device reports poses in.
final class DVSpatialConvention {
  const DVSpatialConvention({
    this.units = DVSceneUnits.meters,
    this.upAxis = DVSceneUpAxis.y,
    this.handedness = DVSceneHandedness.right,
  });

  /// OpenXR reference spaces: right-handed, Y up, metres. Also WebXR's, and
  /// RealityKit's.
  static const DVSpatialConvention openXR = DVSpatialConvention();

  final DVSceneUnits units;
  final DVSceneUpAxis upAxis;
  final DVSceneHandedness handedness;

  /// Takes a point in this convention to world space. The same conversion a
  /// scene document with these units, up axis and handedness gets.
  DVMat4 get toWorld => DVSceneGraph.basisFor(
        units: units,
        upAxis: upAxis,
        handedness: handedness,
      );

  /// A pose the device reported, as a world pose.
  ///
  /// A pose is a transform, not a point, so it converts by conjugation --
  /// `C * P * C^-1` -- and not by `C * P`. The one-sided product still gives
  /// a plausible position, and a mirrored rotation whenever the conventions
  /// differ in handedness: content renders inside out and turns the wrong
  /// way as the user walks round it.
  ///
  /// A non-finite position or a rotation that is not a unit quaternion is
  /// refused rather than normalised: a device that reports one is broken, and
  /// quietly fixing it would hide that.
  DVSpatialPose poseToWorld(DVVec3 position, DVQuat orientation) {
    if (!position.isFinite) {
      throw ArgumentError.value(position, 'position', 'must be finite');
    }
    if (!orientation.isFinite || (orientation.length - 1).abs() > 1e-6) {
      throw ArgumentError.value(orientation, 'orientation', 'must be a unit quaternion');
    }
    final DVMat4 c = toWorld;
    final DVMat4 world =
        c * DVMat4.compose(position, orientation, DVVec3.one) * c.inverse()!;
    return DVSpatialPose(
      position: world.translation,
      orientation: _rotationOf(world),
    );
  }
}

/// The rotation in the upper 3x3 of a matrix with no scale, as a unit
/// quaternion (Shoemake's method).
DVQuat _rotationOf(DVMat4 m) {
  final s = m.storage;
  final double m00 = s[0], m01 = s[4], m02 = s[8];
  final double m10 = s[1], m11 = s[5], m12 = s[9];
  final double m20 = s[2], m21 = s[6], m22 = s[10];
  final double trace = m00 + m11 + m22;
  double x, y, z, w;
  if (trace > 0) {
    final double r = math.sqrt(1 + trace) * 2;
    w = 0.25 * r;
    x = (m21 - m12) / r;
    y = (m02 - m20) / r;
    z = (m10 - m01) / r;
  } else if (m00 > m11 && m00 > m22) {
    final double r = math.sqrt(1 + m00 - m11 - m22) * 2;
    x = 0.25 * r;
    y = (m10 + m01) / r;
    z = (m02 + m20) / r;
    w = (m21 - m12) / r;
  } else if (m11 > m22) {
    final double r = math.sqrt(1 + m11 - m00 - m22) * 2;
    y = 0.25 * r;
    x = (m10 + m01) / r;
    z = (m21 + m12) / r;
    w = (m02 - m20) / r;
  } else {
    final double r = math.sqrt(1 + m22 - m00 - m11) * 2;
    z = 0.25 * r;
    x = (m02 + m20) / r;
    y = (m21 + m12) / r;
    w = (m10 - m01) / r;
  }
  final double l = math.sqrt(x * x + y * y + z * z + w * w);
  return DVQuat(x / l, y / l, z / l, w / l);
}
