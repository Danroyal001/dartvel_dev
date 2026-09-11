/// `context.lifecycle.page`, which nothing could reach.
///
/// The specification writes it as
///
/// ```dart
/// context.lifecycle.page.listen((state) {
///   if (state == DVPageLifecycle.active) DV.log('page_view');
/// });
/// ```
///
/// and a page's `context` is a `BuildContext`. There was no `lifecycle`
/// extension on `BuildContext` at all, so that line did not compile in a
/// page; and `DVContextLifecycle.page` threw for want of a signal, because
/// the only thing that ever built a `DVContext` was `DV.transaction`, which
/// passes a transaction signal and nothing else.
///
/// So the enum existed, the signal type existed, the getter existed and its
/// refusal message existed. What was missing is the one thing that makes any
/// of it observable: something that creates a page's signal and moves it.
///
/// The states are driven by the widget lifecycle rather than announced by
/// the router, because the router knows when it built a route and not when
/// the page it built is on screen. `active` is set after the first frame for
/// the same reason `DV.lifecycle.app` reaches `ready` there: a widget that
/// has been constructed is not a page somebody can see.
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

/// The page lifecycle signal a subtree can reach.
///
/// Inherited rather than global: two pages can be alive at once -- one
/// leaving while the next enters, and both live in a tab workspace -- and a
/// single process-wide signal would report whichever moved last for both.
class DVPageLifecycleScope extends InheritedWidget {
  const DVPageLifecycleScope({
    super.key,
    required this.signal,
    required super.child,
  });

  final DVLifecycleSignal<DVPageLifecycle> signal;

  static DVLifecycleSignal<DVPageLifecycle>? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DVPageLifecycleScope>()
          ?.signal;

  @override
  bool updateShouldNotify(DVPageLifecycleScope old) => old.signal != signal;
}

/// Wraps a page and moves its lifecycle.
///
/// Generated around every page route. The transitions are the ones a widget
/// can actually witness:
///
///   * `created` when the state is created,
///   * `ready` at the end of the first build, when there is something to
///     show,
///   * `active` after the first frame, when there is something on screen,
///   * `disposing` and then `disposed` on the way out.
///
/// The states the specification lists that are not here -- resolving,
/// loading, entering, leaving, inactive, failed -- belong to a data fetch and
/// a route transition, which this layer does not own. They are named as
/// absent rather than emitted at moments that merely resemble them: a page
/// reporting `loading` when nothing is loading is worse than one that never
/// says so.
class DVPageLifecycleHost extends StatefulWidget {
  const DVPageLifecycleHost({super.key, required this.child});

  final Widget child;

  @override
  State<DVPageLifecycleHost> createState() => _DVPageLifecycleHostState();
}

/// Work that belongs to a running application: started with its first page
/// on screen and stopped with its last.
///
/// A timer started anywhere else belongs to nothing. The client schedules
/// used to start theirs when the router was created: nothing ever cancelled
/// it, a second router started a second one beside it so every schedule ran
/// twice, and every widget test that built the router ended with the timer
/// still running. Every route puts its page in a [DVPageLifecycleHost], so
/// whether a page is on screen is something the framework already knows.
///
/// Counted rather than tied to one page, because two are mounted at once
/// whenever one is leaving as the next arrives, and stopping between them
/// would restart the work on every navigation.
class DVShowingPages {
  const DVShowingPages._();

  static int _showing = 0;
  static final Map<String, ({void Function() start, void Function() stop})>
      _jobs = <String, ({void Function() start, void Function() stop})>{};

  /// Whether any page is on screen.
  static bool get isShowing => _showing > 0;

  /// Runs [start] while a page is on screen and [stop] when the last one
  /// goes -- now, if one already is.
  ///
  /// Registering the same [id] again replaces the earlier job, stopping it
  /// first if it was running: a second registration is a second router, and
  /// two copies of the same work are never what either meant.
  static void run(
    String id, {
    required void Function() start,
    required void Function() stop,
  }) {
    final previous = _jobs.remove(id);
    if (previous != null && isShowing) previous.stop();
    _jobs[id] = (start: start, stop: stop);
    if (isShowing) start();
  }

  /// Stops [id] if it is running and forgets it.
  static void cancel(String id) {
    final job = _jobs.remove(id);
    if (job != null && isShowing) job.stop();
  }

  static void _enter() {
    if (_showing++ > 0) return;
    for (final job in _jobs.values.toList()) {
      job.start();
    }
  }

  static void _leave() {
    if (_showing == 0 || --_showing > 0) return;
    for (final job in _jobs.values.toList()) {
      job.stop();
    }
  }

  /// Forgets every job and every page, for tests.
  @visibleForTesting
  static void reset() {
    _showing = 0;
    _jobs.clear();
  }
}

class _DVPageLifecycleHostState extends State<DVPageLifecycleHost> {
  final DVMutableLifecycleSignal<DVPageLifecycle> _signal =
      DVMutableLifecycleSignal<DVPageLifecycle>(DVPageLifecycle.created);
  bool _framed = false;

  @override
  void initState() {
    super.initState();
    DVShowingPages._enter();
  }

  @override
  void dispose() {
    DVShowingPages._leave();
    // Both, in order. A listener watching for the page going away sees the
    // intent and then the fact, which is the difference between "this is
    // ending" and "this has ended" -- and the second is the last thing it
    // will ever see, so it has to arrive.
    _signal.set(DVPageLifecycle.disposing);
    _signal.set(DVPageLifecycle.disposed);
    unawaited(_signal.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_framed) {
      _framed = true;
      _signal.set(DVPageLifecycle.ready);
      // After the frame, not at the end of build: a widget that has been
      // built is not a page somebody can see, which is the same reason the
      // application signal reaches ready in this callback rather than at the
      // end of configuration.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _signal.set(DVPageLifecycle.active);
      });
    }
    return DVPageLifecycleScope(signal: _signal, child: widget.child);
  }
}

/// `context.lifecycle` in a page.
extension DVLifecycleContextX on BuildContext {
  /// The lifecycles this context is inside.
  ///
  /// Only the page one is a page's to have. Reading `request` or
  /// `transaction` here throws the message those getters already carried,
  /// which is the honest answer: a backend function's request and a
  /// transaction's progress are not facts about a widget.
  DVContextLifecycle get lifecycle => DVContextLifecycle(
        page: DVPageLifecycleScope.maybeOf(this),
      );
}
