import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('an orbit camera starts at the yaw and pitch it was given', () {
    const DVSceneCameraData data = DVSceneCameraData.orbit(distance: 10, yawDegrees: 90, pitchDegrees: 30);
    final DVSceneView view = DVSceneView.fromCamera(data);
    expect(view.yaw, closeTo(math.pi / 2, 1e-9));
    expect(view.pitch, closeTo(math.pi / 6, 1e-9));
    // Raised 30 degrees, so the eye is above the target by distance * sin(30).
    expect(view.eye.y, closeTo(5, 1e-9));
  });

  test('the angles round-trip through the document, and zero is not written', () {
    const DVSceneCameraData angled = DVSceneCameraData.orbit(distance: 4, yawDegrees: -20, pitchDegrees: 35);
    final DVSceneCameraData back = DVSceneCameraData.fromJson(angled.toJson(), 'camera');
    expect(back.orbitYawDegrees, -20);
    expect(back.orbitPitchDegrees, 35);
    final Map<String, Object?> flat = (const DVSceneCameraData.orbit(distance: 4).toJson()['orbit'])! as Map<String, Object?>;
    expect(flat.containsKey('yaw'), isFalse);
    expect(flat.containsKey('pitch'), isFalse);
  });

  test('a pitch past straight up or down is refused with its path', () {
    expect(
      () => DVSceneCameraData.fromJson(<String, Object?>{
        'projection': 'perspective',
        'orbit': <String, Object?>{'distance': 4, 'pitch': 120},
      }, 'camera'),
      throwsA(isA<DV3DSceneFormatException>().having((e) => e.toString(), 'message', contains('camera.orbit.pitch'))),
    );
  });
}
