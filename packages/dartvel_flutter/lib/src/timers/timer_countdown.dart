/// A timer's countdown on screen, and what a screen reader hears of it.
library dartvel_flutter.timers.timer_countdown;

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart' show DVModifier, DVModifierChain, DVText;
import 'timer.dart';
import 'timers.dart';

/// The digits of [timer]'s countdown (`14:05`), with a polite live region
/// that says "Eggs, 15 minutes left" and changes only once a minute, then at
/// 30 and 10 seconds and when it is done.
///
/// The digits themselves are hidden from assistive technology: a live region
/// over a clock that changes every second would talk over everything else on
/// the page for the whole quarter of an hour. Rebuild it from
/// `DV.Timers.watch(context)` and it moves every second.
class const DVTimerCountdown(
  final DVTimer timer, {
  super.key,
  final DateTime? now,
  final DVModifier? modifier,
}) extends StatelessWidget with DVModifierChain<DVTimerCountdown> {
  @override
  DVModifier? get chainModifier => modifier;

  /// The same countdown drawn with [modifier]: `DVTimerCountdown(timer).fontSize(40)`.
  @override
  DVTimerCountdown withModifier(DVModifier modifier) => DVTimerCountdown(timer, key: key, now: now, modifier: modifier);

  @override
  Widget build(BuildContext context) {
    final DateTime at = now ?? DVTimers.instance.now;
    final Duration left = timer.remainingAt(at);
    final String spoken = timer.stateAt(at) == .paused
        ? 'paused, ${dvTimerSpoken(left)}'
        : dvTimerSpoken(left);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${timer.label}, $spoken',
      child: ExcludeSemantics(child: DVText(dvTimerClock(left), modifier)),
    );
  }
}
