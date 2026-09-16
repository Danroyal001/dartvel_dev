/// `updates.check`, `updates.apply` and `updates.rollback` bound to the
/// Shorebird updater.
///
/// The updater is compiled into Shorebird's Flutter engine, so on a build made
/// with it its C API is already in the process: FFI, on Android and iOS alike,
/// with nothing to add to the application and no platform channel. On any
/// other build the symbols are absent and nothing is registered, which is what
/// lets `DV.Updates.check()` say it is unbound rather than pretend.
///
/// The updater's calls block on the network, so each runs on its own isolate.
library;

import 'dart:async';
import 'dart:isolate';

import '../../dartvel_flutter.dart' show DVNativeBridge;
import 'shorebird_process_stub.dart'
    if (dart.library.ffi) 'shorebird_process_ffi.dart';

/// The Shorebird updater's C API, as Dart sees it.
abstract interface class DVShorebirdNative {
  /// SHOREBIRD_UPDATE_ERROR.
  static const int error = -1;

  /// SHOREBIRD_NO_UPDATE.
  static const int noUpdate = 0;

  /// SHOREBIRD_UPDATE_INSTALLED: boots on the next launch.
  static const int updateInstalled = 1;

  /// SHOREBIRD_UPDATE_HAD_ERROR.
  static const int hadError = 2;

  /// SHOREBIRD_UPDATE_IS_BAD_PATCH.
  static const int badPatch = 3;

  /// SHOREBIRD_UPDATE_IN_PROGRESS: another call is already updating.
  static const int inProgress = 4;

  /// Whether every symbol was found.
  bool get linked;

  int currentPatch();
  int nextPatch();
  bool checkForUpdate(String? channel);
  (int, String?) update(String? channel);
}

typedef DVShorebirdRunner = Future<R> Function<R>(R Function() work);

Future<R> _onIsolate<R>(R Function() work) => Isolate.run(work);

abstract final class DVShorebirdUpdates {
  /// Why the bindings were not registered, or null when they were.
  static String? lastFailure;

  /// Registers the three bindings when the running engine carries the
  /// updater. Returns whether it did.
  ///
  /// [native] makes the updater: in a running application the process's own
  /// symbols, looked up again on each isolate that calls them. [run] is where
  /// a call runs, a fresh isolate by default.
  static bool register({
    DVShorebirdNative Function() native = dvShorebirdProcessUpdater,
    DVShorebirdRunner run = _onIsolate,
  }) {
    final DVShorebirdNative probe;
    try {
      probe = native();
    } on Object catch (error) {
      lastFailure = 'the Shorebird updater could not be looked up ($error)';
      return false;
    }
    if (!probe.linked) {
      lastFailure = 'this build was not made with Shorebird\'s engine, so the '
          'Shorebird updater is not in the process and DV.Updates has no '
          'patch source. Build the release with `dartvel updates release`.';
      return false;
    }
    lastFailure = null;

    DVNativeBridge.register('updates.check', (Object? arguments) async {
      final String? track = _track(arguments);
      final (int current, int next, bool downloadable) = await run(() {
        final DVShorebirdNative updater = native();
        final bool downloadable = updater.checkForUpdate(track);
        return (updater.currentPatch(), updater.nextPatch(), downloadable);
      });
      final bool waiting = next > current;
      return <String, Object?>{
        'available': downloadable || waiting,
        if (waiting) 'patchId': '$next',
        'metadata': <String, String>{
          'provider': 'shorebird',
          'currentPatch': '$current',
          'nextPatch': '$next',
          if (waiting && !downloadable) 'restartRequired': 'true',
        },
      };
    });

    DVNativeBridge.register('updates.apply', (Object? arguments) async {
      final String? track = _track(arguments);
      final (int current, int next, int status, String? message) = await run(
        () {
          final DVShorebirdNative updater = native();
          final int current = updater.currentPatch();
          final int before = updater.nextPatch();
          if (before > current) return (current, before, 1, null);
          final (int status, String? message) = updater.update(track);
          return (current, updater.nextPatch(), status, message);
        },
      );
      switch (status) {
        case DVShorebirdNative.updateInstalled:
        case DVShorebirdNative.inProgress:
          return true;
        case DVShorebirdNative.noUpdate:
          throw StateError(
            'The Shorebird updater found no patch to install (running patch '
            '$current, next $next).',
          );
        case DVShorebirdNative.badPatch:
          throw StateError(
            'The downloaded patch was rejected and not installed: '
            '${message ?? 'it did not verify'}.',
          );
        default:
          throw StateError(
            'The Shorebird updater could not install the patch: '
            '${message ?? 'status $status'}.',
          );
      }
    });

    DVNativeBridge.register('updates.rollback', (Object? arguments) async {
      final String? track = _track(arguments);
      final (int current, int next) = await run(() {
        final DVShorebirdNative updater = native();
        // A check is when the updater learns of a rollback and uninstalls
        // the rolled-back patch; the device cannot choose one itself.
        updater.checkForUpdate(track);
        return (updater.currentPatch(), updater.nextPatch());
      });
      if (next < current) return true;
      throw StateError(
        'Nothing has been rolled back for this release (running patch '
        '$current, next $next). A rollback is published for every device '
        'with `dartvel updates rollback`; this device then drops the patch on '
        'its next check.',
      );
    });
    return true;
  }

  /// DV.Updates channels as Shorebird tracks: production is `stable`.
  static String? _track(Object? arguments) {
    final Object? channel = arguments is Map ? arguments['channel'] : null;
    if (channel is! String || channel.isEmpty) return null;
    return channel == 'production' ? 'stable' : channel;
  }
}
