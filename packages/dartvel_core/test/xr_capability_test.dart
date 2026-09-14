// What a target can do in space, reported and never assumed.
//
// The report arrives from a native binding as a payload, and the silent
// failure is a payload read generously: an anchor type this version does not
// know counted as supported, or a missing field defaulted to true, and an
// application offers a control whose call then degrades.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  test('a headset can present all three ways', () {
    final DVSpatialCapability s = DVSpatialCapability.headset();
    expect(s.panels && s.volumes && s.immersive && s.passthrough, isTrue);
    expect(s.input, containsAll(<DVSpatialInput>[DVSpatialInput.hands, DVSpatialInput.gaze]));
    expect(s.anchors, contains(DVAnchorType.world));
    expect(s.supports(DVSpatialSpaceKind.volume), isTrue);
    expect(s.supports(DVSpatialSpaceKind.immersive), isTrue);
  });

  test('glasses are not headsets: a HUD, no volumes, no immersive space', () {
    final DVSpatialCapability s = DVSpatialCapability.glasses();
    expect(s.panels, isTrue);
    expect(s.volumes, isFalse);
    expect(s.immersive, isFalse);
    expect(s.passthrough, isFalse);
    expect(s.anchors, isEmpty);
    expect(s.supports(DVSpatialSpaceKind.volume), isFalse);
  });

  group('persistence', () {
    test('bounded carries its limit, and none and full have none', () {
      expect(const DVSpatialPersistence.bounded(8).limit, 8);
      expect(DVSpatialPersistence.full.limit, isNull);
      expect(DVSpatialPersistence.none.kind, DVSpatialPersistenceKind.none);
    });

    test('a bound below one is refused', () {
      expect(() => const DVSpatialPersistence.bounded(0).limit, throwsArgumentError);
    });
  });

  group('decoding what a binding reported', () {
    test('round-trips', () {
      final DVSpatialCapability s = DVSpatialCapability.headset();
      expect(DVSpatialCapability.fromJson(s.toJson()), s);
      final DVSpatialCapability g = DVSpatialCapability.glasses();
      expect(DVSpatialCapability.fromJson(g.toJson()), g);
    });

    test('a member it does not know is dropped, never claimed', () {
      final DVSpatialCapability s = DVSpatialCapability.fromJson(<String, Object?>{
        'panels': true,
        'volumes': true,
        'input': <Object?>['hands', 'telepathy'],
        'anchors': <Object?>['plane', 'geospatial'],
        'persistence': <String, Object?>{'kind': 'bounded', 'limit': 3},
      });
      expect(s.input, <DVSpatialInput>{DVSpatialInput.hands});
      expect(s.anchors, <DVAnchorType>{DVAnchorType.plane});
      expect(s.persistence, const DVSpatialPersistence.bounded(3));
    });

    test('a field it does not report is false, not true', () {
      final DVSpatialCapability s =
          DVSpatialCapability.fromJson(<String, Object?>{'panels': true});
      expect(s.volumes, isFalse);
      expect(s.immersive, isFalse);
      expect(s.passthrough, isFalse);
      expect(s.occlusion, isFalse);
      expect(s.sceneMesh, isFalse);
      expect(s.persistence, DVSpatialPersistence.none);
    });

    test('a payload that is not a report is a FormatException, not a phone', () {
      // Null is the binding saying "not a headset"; anything else malformed is
      // the binding breaking, which the caller reports as DV-XR-006.
      expect(() => DVSpatialCapability.fromJson('headset'), throwsFormatException);
      expect(() => DVSpatialCapability.fromJson(<String, Object?>{'volumes': 'yes'}),
          throwsFormatException);
    });
  });

  group('volume options', () {
    test('a size must be finite and positive on every axis', () {
      expect(const DVVolumeOptions(size: DVVec3(1.2, 0.8, 0.8)).size.x, 1.2);
      expect(() => DVVolumeOptions.checked(const DVVec3(1, 0, 1)), throwsArgumentError);
      expect(() => DVVolumeOptions.checked(const DVVec3(1, double.infinity, 1)),
          throwsArgumentError);
    });
  });
}
