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
/// pending, nothing animating, no scroll under way, and the browser saying
/// it has time to spare (requestIdleCallback) -- the rows still waiting are
/// taken a few at a time, one step per idle moment, until none are left.
/// A long collection's row (DVNearScreen) is read rather than kept: built
/// without layout, its words, links and headings taken, and let go, with a
/// stand-in carrying them to the screen reader and to find; only cheap rows,
/// up to [DVLazyBackfill.keepBudget] render objects, stay built. A lazy
/// ListView's cache grows to cover it. Each step takes as many things as
/// the last one's frame says fit in [frameBudgetMs], never more than
/// [DVLazyBackfill.perStep]. The first frame is exactly as lazy as before;
/// only the idle time after it is spent.
///
/// Building every row instead, four per step, cost sigmadev.digital's 177-
/// tool catalogue on a phone a JS heap of 50-58 MB against 15-21 MB, and
/// 4-7 frames a second for the fifteen seconds after the first frame against
/// 39-48 (Dartvel 3.47.9 risk check).
///
/// On the web only, where the page is read from the document. On Android and
/// iOS the platform's screen reader scrolls a list itself when it reaches the
/// end of what is built, and there is no browser find. Tests turn it on with
/// [DVLazyBackfill.enabled] and drive it with [DVLazyBackfill.step].
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

  /// Whether its next step is free -- letting go of what it has read, or
  /// waiting for a frame -- and does not count against a step's share.
  bool get backfillCostless;
}

abstract final class DVLazyBackfill {
  /// Whether the waiting rows are built when the page is idle. On by
  /// default on the web; tests set it.
  static bool enabled = kIsWeb;

  /// How long after the first frame, or after anything else drew a frame,
  /// the page must be still before a step runs.
  static const int quietMs = 300;

  /// The most waiting things one step takes a little of.
  static const int perStep = 16;

  /// How long the frame a step causes may take, in milliseconds: the next
  /// step takes fewer things when it took longer, more when it was quick.
  /// A frame at 60 Hz: the page is idle, nothing on it moves, and every
  /// frame costs a raster of the whole screen however little changed (on a
  /// phone's software GL that raster, not the build, was most of the cost),
  /// so fewer, fuller frames are cheaper than many small ones. A debug build's frames say nothing about a
  /// release build's (a frame of one paragraph takes 30-50 ms in a debug
  /// build in Chrome), so there every step takes [perStep].
  static const double frameBudgetMs = 16;

  /// How many render objects rows read while idle may keep built, across
  /// the app; a row past it is let go after it is read.
  static const int keepBudget = 400;

  /// How many things the next step takes, from 1 to [perStep].
  static int _take = 1;

  static final Set<DVBackfillable> _waiting = <DVBackfillable>{};

  static bool _armed = false;

  /// How much the next step takes, from 1 to [perStep]: a lazy list grows
  /// its cache by this many pairs of screens.
  static int get stride => kDebugMode ? perStep : _take;

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
    final Stopwatch frame = Stopwatch();
    final int take = kDebugMode ? perStep : _take;
    int done = 0;
    for (final DVBackfillable item in _waiting.toList()) {
      if (!_waiting.contains(item)) continue;
      if (item.backfillCostless) {
        if (!item.backfillStep()) _waiting.remove(item);
        continue;
      }
      if (done >= take) continue;
      if (!item.backfillStep()) _waiting.remove(item);
      done++;
    }
    if (done > 0) {
      // What the step's frame cost, from its start to its end: build,
      // layout, paint and semantics, not the wait for it.
      SchedulerBinding.instance.scheduleFrameCallback((_) => frame.start());
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final double ms = frame.elapsedMicroseconds / 1000;
        if (ms > frameBudgetMs) {
          _take = take > 1 ? take ~/ 2 : 1;
        } else if (ms < frameBudgetMs / 2) {
          _take = take * 2 > perStep ? perStep : take * 2;
        }
      });
    }
    return _waiting.isNotEmpty;
  }

  static void _arm() {
    if (_armed || _waiting.isEmpty) return;
    _armed = true;
    platform.dvBackfillLater(quietMs, _tick);
  }

  static void _tick(bool idle) {
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
    if (!busy && idle) step();
    _arm();
  }

  /// Forgets everything waiting, for tests.
  @visibleForTesting
  static void reset() {
    _waiting.clear();
    _armed = false;
    _take = 1;
    enabled = kIsWeb;
  }
}
