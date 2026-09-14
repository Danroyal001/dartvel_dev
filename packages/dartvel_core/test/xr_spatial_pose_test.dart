// Spatial poses: what a headset reports, brought into the scene's world.
//
// The failure this guards against is silent. A device reports poses in its
// own convention -- OpenXR and WebXR are right-handed with Y up in metres, a
// left-handed engine mirrors Z, a Z-up tool turns everything on its side --
// and a pose converted by multiplying the basis in on one side only still
// produces a plausible matrix. The content appears, in roughly the right
// place, mirrored: text reads backwards and a model turns the wrong way when
// the user walks round it. Nothing throws.
import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const double _eps = 1e-9;

Matcher _near(DVVec3 v, [double eps = _eps]) => predicate<DVVec3>(
      (DVVec3 a) =>
          (a.x - v.x).abs() < eps &&
          (a.y - v.y).abs() < eps &&
          (a.z - v.z).abs() < eps,
      'within $eps of $v',
    );

void main() {
  group('a pose in the world convention', () {
    test('passes through an OpenXR device unchanged', () {
      final DVSpatialPose pose = DVSpatialPose(
        position: const DVVec3(1, 1.6, -2),
        orientation: DVQuat.axisAngle(DVVec3.up, math.pi / 3),
      );
      final DVSpatialPose world =
          DVSpatialConvention.openXR.poseToWorld(pose.position, pose.orientation);

      expect(world.position, _near(pose.position));
      for (final DVVec3 p in const <DVVec3>[DVVec3(1, 0, 0), DVVec3(0, 0, -1)]) {
        expect(world.matrix.transformPoint(p), _near(pose.matrix.transformPoint(p)));
      }
    });

    test('forward is -Z and up is +Y, the scene camera convention', () {
      final DVSpatialPose turned = DVSpatialPose(
        position: DVVec3.zero,
        orientation: DVQuat.axisAngle(DVVec3.up, math.pi / 2),
      );
      // Right-hand rule: a quarter turn about +Y takes -Z to -X.
      expect(turned.forward, _near(const DVVec3(-1, 0, 0)));
      expect(turned.up, _near(DVVec3.up));
    });
  });

  group('a pose from a device in another convention', () {
    // Every point the device places, placed through the converted pose, must
    // land where converting the device's own answer puts it. That is the
    // definition of a change of basis, and it is what a one-sided multiply
    // gets wrong.
    void expectConjugated(DVSpatialConvention convention, DVVec3 position, DVQuat orientation) {
      final DVSpatialPose world = convention.poseToWorld(position, orientation);
      final DVMat4 c = convention.toWorld;
      final DVMat4 device = DVMat4.compose(position, orientation, DVVec3.one);
      for (final DVVec3 p in const <DVVec3>[
        DVVec3(1, 0, 0),
        DVVec3(0, 1, 0),
        DVVec3(0, 0, 1),
        DVVec3(0.3, -2, 5),
      ]) {
        final DVVec3 inDeviceUnits = p * (1 / convention.units.metersPerUnit);
        expect(
          world.matrix.transformPoint(c.transformPoint(inDeviceUnits)),
          _near(c.transformPoint(device.transformPoint(inDeviceUnits)), 1e-9),
          reason: 'point $p through a ${convention.handedness.name}-handed '
              '${convention.upAxis.name}-up device',
        );
      }
      expect(world.matrix.determinant3, closeTo(1, 1e-9),
          reason: 'a pose is a rotation; a mirrored one renders inside out');
    }

    test('left-handed, Y up: two metres forward is -Z, and it does not mirror', () {
      const DVSpatialConvention leftHanded = DVSpatialConvention(
        handedness: DVSceneHandedness.left,
      );
      final DVSpatialPose world =
          leftHanded.poseToWorld(const DVVec3(0, 1.5, 2), DVQuat.identity);
      expect(world.position, _near(const DVVec3(0, 1.5, -2)));

      expectConjugated(
        leftHanded,
        const DVVec3(0.5, 1.5, 2),
        DVQuat.axisAngle(const DVVec3(1, 2, 0.5), 0.7),
      );
    });

    test('Z up in centimetres: units and axis both convert', () {
      const DVSpatialConvention zUpCm = DVSpatialConvention(
        units: DVSceneUnits.centimeters,
        upAxis: DVSceneUpAxis.z,
      );
      final DVSpatialPose world =
          zUpCm.poseToWorld(const DVVec3(0, 0, 160), DVQuat.identity);
      expect(world.position, _near(const DVVec3(0, 1.6, 0), 1e-12));

      expectConjugated(
        zUpCm,
        const DVVec3(20, -30, 160),
        DVQuat.axisAngle(const DVVec3(0, 0, 1), 1.1),
      );
    });

    test('left-handed and Z up together', () {
      expectConjugated(
        const DVSpatialConvention(
          upAxis: DVSceneUpAxis.z,
          handedness: DVSceneHandedness.left,
        ),
        const DVVec3(1, 2, 3),
        DVQuat.axisAngle(const DVVec3(-1, 0.2, 1), 2.4),
      );
    });

    test('a non-finite or non-unit orientation is refused, not normalised', () {
      expect(
        () => DVSpatialConvention.openXR
            .poseToWorld(DVVec3.zero, const DVQuat(0, 0, 0, 2)),
        throwsArgumentError,
      );
      expect(
        () => DVSpatialConvention.openXR
            .poseToWorld(const DVVec3(double.nan, 0, 0), DVQuat.identity),
        throwsArgumentError,
      );
    });
  });

  group('a head pose as a scene camera', () {
    test('looks where the head faces, from where the head is', () {
      final DVSpatialPose head = DVSpatialPose(
        position: const DVVec3(0, 1.6, 0),
        orientation: DVQuat.axisAngle(DVVec3.up, math.pi / 2),
      );
      final DVSceneView view = head.view(fovYDegrees: 90);

      expect(view.eye, _near(const DVVec3(0, 1.6, 0)));
      // Facing -X after a quarter turn: a point two metres along -X is drawn
      // at the centre of the viewport, and a point behind is not drawn.
      final DVVec3? centre = view.project(const DVVec3(-2, 1.6, 0), 200, 100);
      expect(centre, isNotNull);
      expect(centre!.x, closeTo(100, 1e-6));
      expect(centre.y, closeTo(50, 1e-6));
      expect(view.project(const DVVec3(2, 1.6, 0), 200, 100), isNull);
    });
  });

  test('a pose never prints where somebody is', () {
    // Head and hand poses are body data: the specification keeps them out of
    // logs by construction, and a toString is how a value reaches a log.
    const DVSpatialPose pose = DVSpatialPose(
      position: DVVec3(1.25, 1.75, -3.5),
      orientation: DVQuat.identity,
    );
    expect(pose.toString(), isNot(contains('1.25')));
    expect(pose.toString(), isNot(contains('1.75')));
    expect(pose.toString(), isNot(contains('3.5')));
  });
}
