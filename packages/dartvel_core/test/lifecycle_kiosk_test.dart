// DV.lifecycle.kiosk: the kiosk's state as a read-only lifecycle signal.
//
// The spec: reset emits DV.lifecycle.kiosk transitions (resetting -> active).
// Application code observes it, never assigns it; the runtime drives it.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  final DVLifecycleRegistry lifecycle = DVLifecycleRegistry();
  tearDown(lifecycle.resetForTesting);

  test('is off until a runtime says otherwise', () {
    expect(lifecycle.kiosk.value, DVKioskState.off);
  });

  test('follows what the runtime sets, and reset puts it back', () async {
    final List<DVKioskState> seen = <DVKioskState>[];
    final StreamSubscription<DVKioskState> sub = lifecycle.kiosk.listen(seen.add);
    addTearDown(sub.cancel);
    lifecycle.setKiosk(DVKioskState.active);
    lifecycle.setKiosk(DVKioskState.resetting);
    lifecycle.setKiosk(DVKioskState.active);
    await Future<void>.delayed(Duration.zero);
    expect(seen, <DVKioskState>[DVKioskState.active, DVKioskState.resetting, DVKioskState.active]);
    lifecycle.resetForTesting();
    expect(lifecycle.kiosk.value, DVKioskState.off);
  });

  test('a runtime drives it: resume, reset and staff mode show up as transitions', () async {
    final DVKioskRuntime runtime = DVKioskRuntime(
      DVKioskPolicy.parse(<String, Object?>{
        'kiosk': <String, Object?>{
          'enabled': true,
          'home': '/',
          'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
        },
      }),
      readSecret: (String _) async => '1234',
      lifecycle: lifecycle,
      tickEvery: const Duration(days: 1),
    );
    addTearDown(runtime.stop);
    final List<DVKioskState> seen = <DVKioskState>[];
    final StreamSubscription<DVKioskState> sub = lifecycle.kiosk.listen(seen.add);
    addTearDown(sub.cancel);

    await runtime.resume();
    await runtime.reset(DVKioskResetReason.explicit);
    await runtime.exit(const DVKioskExitRequest.pin('1234'));
    await Future<void>.delayed(Duration.zero);

    expect(seen, <DVKioskState>[
      DVKioskState.active,
      DVKioskState.resetting,
      DVKioskState.active,
      DVKioskState.staffMode,
    ]);
  });
}
