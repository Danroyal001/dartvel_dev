// The device-scope kiosk: the whole application under the declared policy.
//
// Installed at start by the generated runtime when dartvel.kiosk declares a
// device-scope kiosk, and reached as DV.Platform.display.kiosk from then on.
// It owns the runtime -- state, the session clock, the exit method -- and
// asks the platform to hold the policy on resume and to let go on exit,
// keeping what the platform said it held so reduced enforcement is a fact
// the application can show.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart'
    show DVKioskEnforcement, DVKioskExitRequest, DVKioskExitResult, DVKioskPolicy, DVKioskReset, DVKioskResetReason, DVKioskRuntime, DVKioskSignal, DVKioskState, DVKioskTarget;

import 'kiosk.dart';

class DVDeviceKiosk {
  final DVKioskRuntime runtime;
  final DVKioskEnforcement enforcement;
  DVKioskEnforced? _enforced;

  DVDeviceKiosk({required this.runtime, required DVKioskTarget target})
      : enforcement = DVKioskEnforcement.resolve(policy: runtime.policy, target: target);

  DVKioskPolicy get policy => runtime.policy;

  /// The kiosk's state, as a signal.
  DVKioskSignal<DVKioskState> get state => runtime.state;

  /// What the platform is holding right now, or null between exit and
  /// resume, or where it could hold nothing.
  DVKioskEnforced? get enforced => _enforced;

  /// Enters kiosk mode, or returns to it from staff mode, and asks the
  /// platform to hold the policy.
  Future<void> resume() async {
    await runtime.resume();
    try {
      _enforced = await DVKiosk.enforce(policy);
    } catch (_) {
      _enforced = null;
    }
  }

  Future<DVKioskReset> resetSession() => runtime.reset(DVKioskResetReason.explicit);

  /// Leaves kiosk mode through the declared exit method. Granted, the
  /// platform lets go of what it held; refused, nothing changes.
  Future<DVKioskExitResult> exit(DVKioskExitRequest request) async {
    final DVKioskExitResult result = await runtime.exit(request);
    if (result.granted) {
      _enforced = null;
      try {
        await DVKiosk.release();
      } catch (_) {
        // Nothing was held.
      }
    }
    return result;
  }

  Future<void> dispose() async {
    runtime.stop();
    if (_enforced != null) {
      _enforced = null;
      try {
        await DVKiosk.release();
      } catch (_) {
        // Nothing was held.
      }
    }
  }
}
