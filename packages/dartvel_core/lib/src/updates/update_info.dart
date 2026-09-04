/// What a server is offering, and whether this device should take it now.
///
/// In core rather than in the Flutter package because the kiosk policy has a
/// say in the answer and lives here. There used to be two types describing
/// the same fact -- one each side of that boundary -- which is how the two
/// halves of the decision came to be made in different places and joined
/// nowhere.
library;

import 'rollout.dart';

/// Which track a device follows.
enum DVUpdateChannel {
  production,
  beta,
  staging,
  development,
}

/// Why an update this device knows about is not being offered to it.
///
/// The point of naming them separately: "no update" and "not yet" look the
/// same from a support desk and are hours apart, and so do "not your turn",
/// "you pinned a version" and "the window is shut".
enum DVUpdateHold {
  /// The staged rollout has not reached this device.
  rollout,

  /// The application pinned another version.
  versionLock,

  /// Somebody declined exactly this version.
  skipped,

  /// A kiosk that applies updates only inside its maintenance window, and
  /// the window is shut.
  maintenanceWindow,

  /// A kiosk that applies updates only while staff are present.
  staffMode,
}

class DVUpdateInfo {
  const DVUpdateInfo({
    required this.available,
    this.version,
    this.patchId,
    this.required = false,
    this.metadata = const <String, String>{},
    this.rolloutPercent = 100,
    this.hold,
    this.notBefore,
    this.resetsSession = false,
  });

  /// Whether this device should apply this now.
  ///
  /// Not "whether a release exists": every rule with a say has already had
  /// it, so a caller that acts on this is acting on the whole answer rather
  /// than on the first half of one.
  final bool available;

  final String? version;
  final String? patchId;

  /// A minimum supported version rather than a new one. It is not staged, it
  /// does not wait for a window, and a skip does not decline it.
  final bool required;

  final Map<String, String> metadata;

  /// The share of the fleet this release has been let out to, 0 to 100.
  final int rolloutPercent;

  /// Why it is not being offered, when it is not. Null when [available].
  final DVUpdateHold? hold;

  /// When it will be offered, when that is known.
  ///
  /// A maintenance window has an hour. A rollout, a version lock and a wait
  /// for staff do not, and saying so beats inventing one.
  final DateTime? notBefore;

  /// Whether applying it clears the session first.
  ///
  /// True for a required update on a kiosk outside its window: the
  /// specification says a forced update resets the session, and the reason
  /// is the order -- landing it on top of a half-finished order is the thing
  /// being avoided.
  final bool resetsSession;

  /// Whether the staged rollout is what is holding it back.
  bool get heldBackByRollout => hold == DVUpdateHold.rollout;

  /// The same release, held back for [reason].
  DVUpdateInfo heldBack(DVUpdateHold reason, {DateTime? notBefore}) =>
      DVUpdateInfo(
        available: false,
        version: version,
        patchId: patchId,
        required: required,
        metadata: metadata,
        rolloutPercent: rolloutPercent,
        hold: reason,
        notBefore: notBefore,
      );

  /// The same release, to be applied after the session is cleared.
  DVUpdateInfo afterReset() => DVUpdateInfo(
        available: true,
        version: version,
        patchId: patchId,
        required: required,
        metadata: metadata,
        rolloutPercent: rolloutPercent,
        resetsSession: true,
      );

  /// The same release, decided against this device's place in the rollout.
  ///
  /// A release marked [required] is not staged: the fleet is broken without
  /// it, and withholding it on a hash would be the framework overruling the
  /// person who marked it.
  DVUpdateInfo forDevice(String? deviceId) {
    if (!available || required || rolloutPercent >= 100) return this;
    final bool reached = DVUpdateRollout.includes(
      deviceId: deviceId ?? '',
      version: version ?? '',
      percent: rolloutPercent,
    );
    return reached ? this : heldBack(DVUpdateHold.rollout);
  }

  factory DVUpdateInfo.fromMap(Map<Object?, Object?> map) {
    final Object? rawMetadata = map['metadata'];
    final Map<String, String> metadata = rawMetadata is Map
        ? rawMetadata.map(
            (Object? key, Object? value) =>
                MapEntry<String, String>('$key', '$value'),
          )
        : const <String, String>{};
    return DVUpdateInfo(
      available: map['available'] == true,
      version: map['version']?.toString(),
      patchId: map['patchId']?.toString(),
      required: map['required'] == true,
      metadata: metadata,
      rolloutPercent: _percentOf(map['rollout'] ?? metadata['rollout']),
    );
  }

  /// A rollout percentage as the server sent it, which may be a number, a
  /// string, or absent. Anything unreadable means the release is not staged,
  /// because a rollout nobody can parse must not silently withhold an update.
  static int _percentOf(Object? raw) {
    if (raw == null) return 100;
    if (raw is num) return raw.round();
    return int.tryParse(raw.toString().trim()) ?? 100;
  }
}
