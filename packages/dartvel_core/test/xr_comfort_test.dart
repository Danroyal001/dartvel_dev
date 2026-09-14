// Comfort is policy, not advice, and a frame budget is a sustained measure.
//
// Both fail silently. Smooth locomotion with nothing to soften it ships and
// makes somebody sick; a monitor that reports every hitch is muted within a
// day, and one that averages over the whole session never reports at all.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('comfort', () {
    test('smooth locomotion with no comfort option reports DV-XR-005 and gets a vignette', () {
      final DVComfortResolution r = DVComfort.resolve(
        const DVComfortOptions(locomotion: <DVLocomotion>{DVLocomotion.smooth}),
      );
      expect(r.codes, <String>['DV-XR-005']);
      expect(r.effective.vignette, isTrue,
          reason: 'policy: the vignette is applied, not suggested');
      expect(r.effective.locomotion, contains(DVLocomotion.smooth));
    });

    test('smooth locomotion alongside teleport or snap turn, or with a vignette, is fine', () {
      for (final DVComfortOptions options in <DVComfortOptions>[
        const DVComfortOptions(
            locomotion: <DVLocomotion>{DVLocomotion.smooth, DVLocomotion.teleport}),
        const DVComfortOptions(
            locomotion: <DVLocomotion>{DVLocomotion.smooth, DVLocomotion.snapTurn}),
        const DVComfortOptions(
            locomotion: <DVLocomotion>{DVLocomotion.smooth}, vignette: true),
      ]) {
        expect(DVComfort.resolve(options).codes, isEmpty);
      }
    });

    test('reduced motion removes smooth locomotion where another way to move exists', () {
      final DVComfortResolution r = DVComfort.resolve(
        const DVComfortOptions(
            locomotion: <DVLocomotion>{DVLocomotion.smooth, DVLocomotion.teleport}),
        reducedMotion: true,
      );
      expect(r.effective.locomotion, <DVLocomotion>{DVLocomotion.teleport});
    });

    test('and forces the vignette where smooth is the only way to move', () {
      final DVComfortResolution r = DVComfort.resolve(
        const DVComfortOptions(locomotion: <DVLocomotion>{DVLocomotion.smooth}, vignette: true),
        reducedMotion: true,
      );
      expect(r.effective.locomotion, <DVLocomotion>{DVLocomotion.smooth});
      expect(r.effective.vignette, isTrue);
      expect(r.codes, isEmpty);
    });

    test('no locomotion at all needs nothing', () {
      expect(DVComfort.resolve(const DVComfortOptions()).codes, isEmpty);
    });
  });

  group('frame budget', () {
    const Duration at90 = Duration(microseconds: 11111);
    const Duration at50 = Duration(milliseconds: 20);

    int feed(DVSpatialFrameMonitor m, Duration interval, Duration total) {
      int reports = 0;
      for (Duration t = Duration.zero; t < total; t += interval) {
        if (m.record(interval)) reports++;
      }
      return reports;
    }

    test('on target, nothing is reported', () {
      final DVSpatialFrameMonitor m = DVSpatialFrameMonitor(targetFps: 90);
      expect(feed(m, at90, const Duration(seconds: 5)), 0);
    });

    test('a sustained drop is reported once, not once per frame', () {
      final DVSpatialFrameMonitor m = DVSpatialFrameMonitor(targetFps: 90);
      feed(m, at90, const Duration(seconds: 1));
      expect(feed(m, at50, const Duration(seconds: 6)), 1);
      expect(m.measuredFps, closeTo(50, 1));
    });

    test('a single hitch is not sustained', () {
      final DVSpatialFrameMonitor m = DVSpatialFrameMonitor(targetFps: 90);
      feed(m, at90, const Duration(seconds: 2));
      expect(m.record(const Duration(milliseconds: 100)), isFalse);
      expect(feed(m, at90, const Duration(seconds: 2)), 0);
    });

    test('recovering ends the episode, so the next drop is news', () {
      final DVSpatialFrameMonitor m = DVSpatialFrameMonitor(targetFps: 90);
      expect(feed(m, at50, const Duration(seconds: 3)), 1);
      expect(feed(m, at90, const Duration(seconds: 3)), 0);
      expect(feed(m, at50, const Duration(seconds: 3)), 1);
    });

    test('reprojected frames are counted', () {
      final DVSpatialFrameMonitor m = DVSpatialFrameMonitor(targetFps: 90);
      m.record(at90, reprojected: true);
      m.record(at90);
      m.record(at90, reprojected: true);
      expect(m.reprojectionMisses, 2);
    });

    test('a target that is not a positive rate is refused', () {
      expect(() => DVSpatialFrameMonitor(targetFps: 0), throwsArgumentError);
    });
  });
}
