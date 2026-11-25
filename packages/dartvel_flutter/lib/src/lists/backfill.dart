/// What lazy lists have not built yet, built while the page is idle.
///
/// Every scrollable DVBox list builds only the rows near the screen, and a
/// long DVBox list in a page that scrolls holds a place for its later rows
/// (DVNearScreen). That keeps the first frame fast, and on the web it left
/// the rest of the page out of everything that reads the page rather than
/// looks at it. A row that is not built has no semantics node, so a screen
/// reader reading line by line stopped at the last row built and never
/// reached the footer; and it has no text, so the browser's find, after a
/// navigation inside the app, searched only what was on screen (Tori and
/// Learnacer, Dartvel 3.47.7).
///
/// So once the first frame is drawn and the page is idle -- no frame
/// pending, nothing animating, no scroll under way -- the rows still waiting
/// are built a few at a time, one step per idle moment, until none are left.
/// A row built this way stays built, as a row scrolled to does. The first
/// frame is exactly as lazy as before; only the idle time after it is spent.
///
/// On the web only, where the page is read from the document. On Android and
/// iOS the platform's screen reader scrolls a list itself when it reaches the
/// end of what is built, and there is no browser find. Tests turn it on with
/// [DVLazyBackfill.enabled] and drive it with [DVLazyBackfill.step].
///
/// Off unless the application opts in (Dartvel 3.47.9). On long lists the
/// building kept the main thread busy and the heap high: on a 177-row
/// catalogue at 4x CPU the JS heap peaked at 50-58 MB instead of 15-21 MB and
/// the first 15 s ran at 4-7 fps instead of about 45. Until it is cheap
/// enough, `dartvel.web.lazyBackfill: true` in pubspec.yaml turns it on (the
/// build hands it to the app as the DARTVEL_LAZY_BACKFILL define). With it
/// off, a screen reader and find after an in-app navigation reach what they
/// reached in Dartvel 3.47.8.
///
/// Not in the barrel: there is nothing for an application to call.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'backfill_timer_stub.dart' if (dart.library.js_interop) 'backfill_timer_web.dart' as platform;

/// Something a lazy list has not built all of yet.
abstract class DVBackfillable {
  /// Builds a little more of what is waiting. False once nothing is left,
  /// and it is dropped.
  bool backfillStep();
}

/// Whether the idle backfill starts on: on the web, and only when the
/// application opted in.
@visibleForTesting
bool dvLazyBackfillDefault({required bool isWeb, required bool optedIn}) => isWeb && optedIn;

abstract final class DVLazyBackfill {
  /// Whether the application opted in: `dartvel.web.lazyBackfill: true`,
  /// handed to the app as the DARTVEL_LAZY_BACKFILL define.
  static const bool optedIn = bool.fromEnvironment('DARTVEL_LAZY_BACKFILL');

  /// Whether the waiting rows are built when the page is idle. Off unless
  /// the application opted in, and only on the web; tests set it.
  static bool enabled = dvLazyBackfillDefault(isWeb: kIsWeb, optedIn: optedIn);

  /// How long after the first frame, or after anything else drew a frame,
  /// the page must be still before a step runs.
  static const int quietMs = 300;

  /// How many waiting things one step builds a little of.
  static const int perStep = 4;

  static final Set<DVBackfillable> _waiting = <DVBackfillable>{};

  static bool _armed = false;

  /// Whether anything is waiting.
  static bool get pending => _waiting.isNotEmpty;

  /// A lazy list or row with something not built.
  static void register(DVBackfillable item) {
    if (!enabled) return;
    _waiting.add(item);
    _arm();
  }

  /// It went away, or was built some other way.
  static void unregister(DVBackfillable item) => _waiting.remove(item);

  /// Builds a little of the first [perStep] things waiting. True when more
  /// is left for another step. The frame the step asked for draws it.
  static bool step() {
    int done = 0;
    for (final DVBackfillable item in _waiting.toList()) {
      if (done >= perStep) break;
      if (!_waiting.contains(item)) continue;
      if (!item.backfillStep()) _waiting.remove(item);
      done++;
    }
    return _waiting.isNotEmpty;
  }

  static void _arm() {
    if (_armed || _waiting.isEmpty) return;
    _armed = true;
    platform.dvBackfillLater(quietMs, _tick);
  }

  static void _tick() {
    _armed = false;
    if (!enabled || _waiting.isEmpty) return;
    final SchedulerBinding scheduler = SchedulerBinding.instance;
    // Not while the page is busy: a frame is coming (a scroll, a drag, an
    // animation, a build), or the first frame is still held back (the
    // splash, a page waiting for its data): what is built then lands in the
    // first frame and makes it slower.
    final bool busy = scheduler.hasScheduledFrame ||
        scheduler.transientCallbackCount > 0 ||
        scheduler.schedulerPhase != SchedulerPhase.idle ||
        !WidgetsBinding.instance.sendFramesToEngine;
    if (!busy) step();
    _arm();
  }

  /// Forgets everything waiting, for tests.
  @visibleForTesting
  static void reset() {
    _waiting.clear();
    _armed = false;
    enabled = dvLazyBackfillDefault(isWeb: kIsWeb, optedIn: optedIn);
  }
}
