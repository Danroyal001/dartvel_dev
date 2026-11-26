import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start timers-start
// pubspec.yaml: dartvel: { timers: true }
// Called from the tap: that gesture lets a browser ask for notifications and
// play the chime later. An id of your own makes a second tap give back the
// timer already running.
Future<void> boilEggs() async {
  await DV.Timers.start(
    'Boil the eggs',
    const Duration(minutes: 15),
    id: 'eggs',
  );
}
// docs:end

// docs:start timers-list
// Rebuilds on every change and once a second while a timer counts down.
// DVTimerCountdown shows 14:05 and tells a screen reader "Boil the eggs,
// 15 minutes left" once a minute, not every second.
Widget timerList(BuildContext context) => DVBox.list(<Widget>[
      for (final DVTimer timer in DV.Timers.watch(context))
        DVBox.row(<Widget>[
          DVTimerCountdown(timer),
          if (timer.stateAt(DV.Timers.now) == DVTimerState.ringing)
            DVText('Snooze 5 min').modifier(const DVModifier()
                .tooltip('Ring again in 5 minutes')
                .onTap(() => DV.Timers.snooze(timer.id, const Duration(minutes: 5)))),
          DVText('Stop').modifier(const DVModifier()
              .tooltip('Stop this timer')
              .onTap(() => DV.Timers.dismiss(timer.id))),
        ]),
    ]);
// docs:end
