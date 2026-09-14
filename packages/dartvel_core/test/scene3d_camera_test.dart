// Cameras: from a pixel to a ray, and from a point to a pixel.
//
// A tap is only as right as this conversion. A ray built with the wrong
// aspect, or a point behind the camera projected through to the screen, puts
// the pick on a node the user never touched.
import 'dart:math' as math;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

double _distanceToRay(DVVec3 point, DVRay ray) {
  final DVVec3 d = ray.direction.normalized();
  final DVVec3 v = point - ray.origin;
  return (v - d * v.dot(d)).length;
}

void main() {
  test('an orbit camera at yaw 0 and pitch 0 looks down -Z at its target', () {
    final DVSceneView view = DVSceneView.orbit(
        target: const DVVec3(1, 2, 3), distance: 5);
    expect(view.eye, const DVVec3(1, 2, 8));
  });

  test('the centre of the viewport is a ray from the eye through the target',
      () {
    final DVSceneView view = DVSceneView.orbit(
        target: DVVec3.zero, distance: 4, yaw: 0.6, pitch: 0.3);
    final DVRay ray = view.rayAt(200, 100, 400, 200);
    expect(_distanceToRay(DVVec3.zero, ray), lessThan(1e-9));
    expect((ray.origin - view.eye).length, lessThan(1e-9));
  });

  test('projecting the target lands in the centre', () {
    final DVSceneView view =
        DVSceneView.orbit(target: DVVec3.zero, distance: 4, yaw: -1);
    final DVVec3 p = view.project(DVVec3.zero, 800, 450)!;
    expect(p.x, closeTo(400, 1e-9));
    expect(p.y, closeTo(225, 1e-9));
  });

  test('a projected point unprojects to a ray through that point', () {
    final DVSceneView view = DVSceneView(
        eye: const DVVec3(3, 2, 6), target: const DVVec3(0, 0.5, 0), fovYDegrees: 60);
    const DVVec3 point = DVVec3(-0.7, 1.3, 0.4);
    for (final (double w, double h) in <(double, double)>[(800, 450), (300, 900)]) {
      final DVVec3 pixel = view.project(point, w, h)!;
      final DVRay ray = view.rayAt(pixel.x, pixel.y, w, h);
      expect(_distanceToRay(point, ray), lessThan(1e-9), reason: '$w x $h');
    }
  });

  test('screen y grows downward, as Flutter lays out', () {
    final DVSceneView view = DVSceneView.orbit(target: DVVec3.zero, distance: 4);
    expect(view.project(const DVVec3(0, 1, 0), 400, 400)!.y, lessThan(200));
    expect(view.project(const DVVec3(1, 0, 0), 400, 400)!.x, greaterThan(200));
  });

  test('a point behind the camera does not project onto the screen', () {
    final DVSceneView view = DVSceneView.orbit(target: DVVec3.zero, distance: 4);
    expect(view.project(const DVVec3(0, 0, 10), 400, 400), isNull);
  });

  test('orbiting clamps pitch short of the pole, so the view never flips', () {
    DVSceneView view = DVSceneView.orbit(target: DVVec3.zero, distance: 4);
    view = view.orbitBy(pitch: 10);
    expect(view.pitch, lessThan(math.pi / 2));
    expect(view.project(const DVVec3(0, 0, -1), 400, 400), isNotNull);
    view = view.orbitBy(pitch: -20);
    expect(view.pitch, greaterThan(-math.pi / 2));
  });

  test('zooming keeps the camera in front of its near plane', () {
    final DVSceneView view = DVSceneView.orbit(target: DVVec3.zero, distance: 4)
        .orbitBy(zoom: 1000);
    expect(view.distance, greaterThan(view.near));
  });

  test('a camera built from a document node uses its orbit and projection', () {
    final DVSceneView view = DVSceneView.fromCamera(
      const DVSceneCameraData.orbit(
          target: DVVec3(0, 1, 0), distance: 2.4, fovYDegrees: 30),
    );
    expect(view.eye, const DVVec3(0, 1, 2.4));
    expect(view.fovYDegrees, 30);
  });

  test('tapping where a node is drawn picks it, and not after it moves', () {
    final DVSceneGraph graph = DVSceneGraph(DV3DSceneDocument(id: 's', nodes: <DVSceneNodeData>[
      DVSceneNodeData.mesh(
        id: 'ball',
        primitive: DVScenePrimitive.sphere(0.25),
        transform: DVTransform(translation: const DVVec3(0.8, 0.3, 0)),
      ),
    ]));
    final DVSceneView view = DVSceneView.orbit(target: DVVec3.zero, distance: 4);
    final DVVec3 at = view.project(graph.worldPosition('ball'), 640, 360)!;

    expect(graph.pick(view.rayAt(at.x, at.y, 640, 360))?.nodeId, 'ball');

    graph.setTransform('ball', DVTransform(translation: const DVVec3(-0.8, 0.3, 0)));
    expect(graph.pick(view.rayAt(at.x, at.y, 640, 360)), isNull);
  });
}
