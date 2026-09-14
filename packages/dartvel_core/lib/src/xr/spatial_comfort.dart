/// Comfort policy and the frame budget.
library dartvel.xr.comfort;

import 'dart:collection';

/// How an immersive scene lets the user move.
enum DVLocomotion { teleport, snapTurn, smooth }

/// The comfort options an immersive space offers.
final class DVComfortOptions {
  const DVComfortOptions({
    this.locomotion = const <DVLocomotion>{},
    this.vignette = false,
    this.seated = false,
  });

  final Set<DVLocomotion> locomotion;

  /// Narrowing the view while moving.
  final bool vignette;
  final bool seated;
}

/// What the policy made of what was declared.
final class DVComfortResolution {
  const DVComfortResolution(this.effective, this.codes);

  final DVComfortOptions effective;

  /// `DV-XR-005` when smooth locomotion was offered with nothing to soften
  /// it.
  final List<String> codes;
}

/// Comfort is policy, not advice.
abstract final class DVComfort {
  /// Resolves [declared] against the policy.
  ///
  /// Smooth locomotion needs a comfort option beside it -- teleport, snap
  /// turn, or a vignette. Offered with none, it reports `DV-XR-005` and the
  /// vignette is applied rather than suggested: removing the locomotion
  /// would strand a user in a scene that has no other way to move.
  ///
  /// With [reducedMotion], smooth locomotion is removed where another way to
  /// move exists, and vignetted where it does not.
  static DVComfortResolution resolve(
    DVComfortOptions declared, {
    bool reducedMotion = false,
  }) {
    final Set<DVLocomotion> locomotion = Set<DVLocomotion>.of(declared.locomotion);
    bool vignette = declared.vignette;
    final List<String> codes = <String>[];
    final bool smooth = locomotion.contains(DVLocomotion.smooth);
    final bool alternative = locomotion.contains(DVLocomotion.teleport) ||
        locomotion.contains(DVLocomotion.snapTurn);
    if (smooth && !alternative && !vignette) {
      codes.add('DV-XR-005');
      vignette = true;
    }
    if (reducedMotion && smooth) {
      if (alternative) {
        locomotion.remove(DVLocomotion.smooth);
      } else {
        vignette = true;
      }
    }
    return DVComfortResolution(
      DVComfortOptions(
        locomotion: Set<DVLocomotion>.unmodifiable(locomotion),
        vignette: vignette,
        seated: declared.seated,
      ),
      List<String>.unmodifiable(codes),
    );
  }
}

/// Watches frame intervals against a device profile's target rate.
///
/// Sustained means a whole [sustained] window below [tolerance] of the
/// target, so a single hitch is not reported and neither is every frame of a
/// long drop: one report per episode, and recovering ends the episode.
final class DVSpatialFrameMonitor {
  DVSpatialFrameMonitor({
    required this.targetFps,
    this.sustained = const Duration(seconds: 2),
    this.tolerance = 0.9,
  }) {
    if (!targetFps.isFinite || targetFps <= 0) {
      throw ArgumentError.value(targetFps, 'targetFps', 'must be a positive rate');
    }
    if (sustained <= Duration.zero) {
      throw ArgumentError.value(sustained, 'sustained', 'must be positive');
    }
  }

  final double targetFps;
  final Duration sustained;
  final double tolerance;

  final Queue<int> _window = Queue<int>();
  int _sum = 0;
  bool _inEpisode = false;

  /// Frames the compositor reprojected.
  int reprojectionMisses = 0;

  /// The rate over the last full window; 0 until one has elapsed.
  double measuredFps = 0;

  /// Records one frame. True exactly when a sustained drop begins, which is
  /// when `DV-XR-007` is reported.
  bool record(Duration interval, {bool reprojected = false}) {
    if (reprojected) reprojectionMisses++;
    final int micros = interval.inMicroseconds;
    if (micros <= 0) return false;
    _window.addLast(micros);
    _sum += micros;
    final int span = sustained.inMicroseconds;
    while (_window.length > 1 && _sum - _window.first >= span) {
      _sum -= _window.removeFirst();
    }
    if (_sum < span) return false;
    measuredFps = _window.length * 1e6 / _sum;
    final bool below = measuredFps < targetFps * tolerance;
    if (below && !_inEpisode) {
      _inEpisode = true;
      return true;
    }
    if (!below) _inEpisode = false;
    return false;
  }
}
