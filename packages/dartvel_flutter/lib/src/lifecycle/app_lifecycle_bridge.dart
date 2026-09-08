/// `DV.lifecycle.app`, driven by the platform rather than by two calls at
/// start.
///
/// The signal reported two of its ten states. booting and ready were set by
/// the generated runtime while an application was starting, and nothing ever
/// set another -- so an application observing it to save a draft when it
/// goes into the background never saw `backgrounded`, and one refreshing on
/// the way back never saw the return. The enum said those states existed and
/// nothing produced them, which reads as an application that is never
/// backgrounded rather than as a signal that does not say.
///
/// Flutter reports this already. What was missing is the mapping, and the
/// mapping is where the judgement is: two of Flutter's five states are not
/// what they look like.
library;

import 'package:dartvel_core/dartvel.dart' show DVAppLifecycle;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart' show DV;

/// What [state] means for `DV.lifecycle.app`, or null when it means nothing.
///
/// Separate from the observer so the judgement can be tested without a
/// binding, and so the two cannot drift.
DVAppLifecycle? dvAppLifecycleFor(AppLifecycleState state) {
  switch (state) {
    // Both are the background. Flutter sends hidden before paused on every
    // platform now, and on desktop it is the whole of it: a window that is
    // covered or minimised never reaches paused, so an application that
    // listened only for paused would save nothing on a desktop.
    case AppLifecycleState.hidden:
    case AppLifecycleState.paused:
      return DVAppLifecycle.backgrounded;

    // The settled state, not the transition into it. Reporting `resuming`
    // here would name a moment that has already passed, and an application
    // waiting for `ready` would never get it.
    case AppLifecycleState.resumed:
      return DVAppLifecycle.ready;

    case AppLifecycleState.detached:
      return DVAppLifecycle.shuttingDown;

    // A notification banner, the app switcher, an incoming call: the
    // application is on screen and about to be interrupted. Calling it
    // backgrounded would have an application save a draft and flush its
    // state every time a message arrives, and would say the app went away
    // when it did not. Nothing is a better answer than a wrong one.
    case AppLifecycleState.inactive:
      return null;
  }
}

_DVAppLifecycleObserver? _observer;

/// Starts reporting the platform's application lifecycle on
/// `DV.lifecycle.app`.
///
/// Idempotent. A second observer over the same binding would report every
/// transition twice, and a listener counting them would see each state
/// arrive as many times as something called this.
///
/// Ensures the binding rather than assuming it. The generated runtime calls
/// this from configureDartvelRuntime, which runs while the router is being
/// built -- before runApp, and therefore before runApp would have
/// initialised anything. Reading WidgetsBinding.instance there throws, the
/// application never reaches its first frame, and what that looked like was
/// a site build capturing nothing: "Captured 0 of 4 routes", reported as
/// resource pressure because that is the usual cause.
void dvStartAppLifecycleBridge() {
  if (_observer != null) return;
  final _DVAppLifecycleObserver observer = _DVAppLifecycleObserver();
  _observer = observer;
  WidgetsFlutterBinding.ensureInitialized().addObserver(observer);
}

/// Stops reporting. For tests, and for a host that owns the binding itself.
void dvStopAppLifecycleBridge() {
  final _DVAppLifecycleObserver? observer = _observer;
  if (observer == null) return;
  WidgetsFlutterBinding.ensureInitialized().removeObserver(observer);
  _observer = null;
}

class _DVAppLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final DVAppLifecycle? mapped = dvAppLifecycleFor(state);
    if (mapped == null) return;
    DV.lifecycle.setApp(mapped);
  }
}
