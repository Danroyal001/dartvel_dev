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
/// it has time to spare (requestIdleCallback) -- what is still waiting is
/// taken a little at a time, until none is left.
///
/// A long collection's row (DVNearScreen) is read rather than kept: built
/// apart from the page, never laid out or painted, its words, links and
/// headings taken, and let go, all within the idle moment the browser gave.
/// Reading draws nothing, so it asks for no frame. The rows read land in the
/// page together, in one frame, as stand-ins that carry their words to the
/// screen reader and to find; only cheap rows, up to
/// [DVLazyBackfill.keepBudget] render objects, are built for good. A lazy
/// ListView's cache grows to cover it, as many screens a frame as its last
/// growth says fit in [DVLazyBackfill.growBudgetMs].
///
/// Frames are what cost: every frame on the web rasters the whole screen,
/// however little changed, about 100 ms on sigmadev.digital at 390 px with
/// 4x CPU. Building every row instead, four per step, cost the 177-tool
/// catalogue a JS heap of 50-58 MB against 15-21 MB and 4-7 frames a second
/// for the fifteen seconds after the first frame against 39-48; reading a
/// row or two a frame took over a hundred frames and 40 seconds at 3 frames a
/// second (Dartvel 3.47.9 risk check). The first frame is exactly as lazy as
/// before; only the idle time after it is spent.
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
  /// Does a little more of what is waiting. False once nothing is left,
  /// and it is dropped.
  bool backfillStep();

  /// Whether its steps draw nothing and so ask for no frame: a row read
  /// apart from the page. A lazy list growing its cache changes what is laid
  /// out, and takes a frame.
  bool get backfillFrameless;
}

abstract final class DVLazyBackfill {
  /// Whether the waiting rows are read when the page is idle. On by default
  /// on the web; tests set it.
  static bool enabled = kIsWeb;

  /// How long after the first frame, or after anything else drew a frame,
  /// the page must be still before a step runs.
  static const int quietMs = 300;

  /// The most rows one step reads.
  static const int perStep = 64;

  /// How long rows read but not yet in the page wait for the rest before
  /// they land anyway, in milliseconds: a collection of thousands lands a
  /// part at a time rather than all at the end.
  static const int landAfterMs = 3000;

  /// How long a lazy list's growth may spend building and laying out the
  /// rows it reaches, in milliseconds. The frame's raster comes on top and
  /// does not depend on it: the rows grown into are off screen.
  static const double growBudgetMs = 40;

  /// How many render objects rows read while idle may keep built, across
  /// the app; a row past it is let go after it is read.
  static const int keepBudget = 400;

  static final Set<DVBackfillable> _waiting = <DVBackfillable>{};

  /// Rows read, landing in the page in the next frame step.
  static final List<VoidCallback> _landing = <VoidCallback>[];
  static final Stopwatch _landingSince = Stopwatch();

  static bool _armed = false;

  /// Whether anything is waiting.
  static bool get pending => _waiting.isNotEmpty || _landing.isNotEmpty;

  /// A lazy list or row with something not built.
  static void register(DVBackfillable item) {
    if (!enabled) return;
    _waiting.add(item);
    _arm(quietMs);
  }

  /// It went away, or was built some other way.
  static void unregister(DVBackfillable item) => _waiting.remove(item);

  /// A row has been read: [land] puts what it read in the page, with the
  /// other rows read, in one frame.
  static void land(VoidCallback land) {
    if (_landing.isEmpty) _landingSince..reset()..start();
    _landing.add(land);
  }

  /// Reads rows until [budgetMs] is spent (at least one, at most
  /// [perStep]); then, once nothing is left to read or what was read has
  /// waited [landAfterMs], lands it and grows one lazy list, in one frame.
  /// True when more is left for another step. Without a budget -- a test, a
  /// debug build -- it reads [perStep] rows. Nothing while a frame is
  /// coming.
  static bool step([double? budgetMs]) {
    // A frame is coming: what it builds is dirty now, and a row read now
    // would build it outside its frame. The step waits for the next one.
    if (SchedulerBinding.instance.hasScheduledFrame) return pending;
    final Stopwatch spent = Stopwatch()..start();
    final double budget = budgetMs ?? double.infinity;
    int read = 0;
    for (final DVBackfillable item in _waiting.toList()) {
      if (read >= perStep || (read > 0 && spent.elapsedMicroseconds / 1000 >= budget)) break;
      if (!item.backfillFrameless || !_waiting.contains(item)) continue;
      if (!item.backfillStep()) _waiting.remove(item);
      read++;
    }
    final bool readingLeft = _waiting.any((DVBackfillable item) => item.backfillFrameless);
    if (readingLeft && (_landing.isEmpty || _landingSince.elapsedMilliseconds < landAfterMs)) return true;
    // A frame step: what was read lands, and one lazy list grows, together.
    final List<VoidCallback> landing = List<VoidCallback>.of(_landing);
    _landing.clear();
    for (final VoidCallback land in landing) {
      land();
    }
    for (final DVBackfillable item in _waiting.toList()) {
      if (item.backfillFrameless) continue;
      if (!item.backfillStep()) _waiting.remove(item);
      break;
    }
    return pending;
  }

  static void _arm(int afterMs) {
    if (_armed || !pending) return;
    _armed = true;
    platform.dvBackfillLater(afterMs, _tick);
  }

  static void _tick(double budgetMs) {
    _armed = false;
    if (!enabled || !pending) return;
    final SchedulerBinding scheduler = SchedulerBinding.instance;
    // Not while the page is busy: a frame is coming (a scroll, a drag, an
    // animation, a build), or the first frame is still held back (the
    // splash, a page waiting for its data): what is built then lands in the
    // first frame and makes it slower.
    final bool busy = scheduler.hasScheduledFrame ||
        scheduler.transientCallbackCount > 0 ||
        scheduler.schedulerPhase != SchedulerPhase.idle ||
        !WidgetsBinding.instance.sendFramesToEngine;
    if (busy || budgetMs <= 0) {
      _arm(quietMs);
      return;
    }
    step(budgetMs);
    // A step that only read asked for no frame: the next one runs in the
    // next idle moment. One that drew waits for the page to be still again.
    _arm(scheduler.hasScheduledFrame ? quietMs : 0);
  }

  /// Forgets everything waiting, for tests.
  @visibleForTesting
  static void reset() {
    _waiting.clear();
    _landing.clear();
    _armed = false;
    enabled = kIsWeb;
  }
}
