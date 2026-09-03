// Kiosk enforcement, the Flutter-facing half.
//
// DVKiosk.enforce asks the platform binding to hold the policy -- block the
// escape combos, go fullscreen -- and reports what was actually held, so
// reduced enforcement is a fact the operator sees rather than a silence.
// Every blocked press is reported on [DVKiosk.blocked]; a kiosk runtime can
// treat it as activity and an audit can count it.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVKioskPolicy;

import '../../dartvel_flutter.dart' show DVNativeBridge;
import '../platform/accelerator.dart';
import 'kiosk_keys.dart';

/// What enforcement actually did.
class DVKioskEnforced {
  /// Combos now swallowed device-wide.
  final List<String> blocked;

  /// Combos the policy asked for that the platform could not hold, with why.
  final Map<String, String> unenforced;

  final bool fullscreen;

  /// Whether the pointer is held inside the kiosk's window.
  final bool confined;

  /// Whether system notifications the framework would send are held back.
  final bool notificationsSuppressed;

  const DVKioskEnforced({
    required this.blocked,
    this.unenforced = const <String, String>{},
    this.fullscreen = false,
    this.confined = false,
    this.notificationsSuppressed = false,
  });

  factory DVKioskEnforced.fromMap(Map<Object?, Object?> map) => DVKioskEnforced(
        blocked: <String>[for (final Object? b in (map['blocked'] as List?) ?? const <Object?>[]) '$b'],
        unenforced: <String, String>{
          for (final MapEntry<Object?, Object?> e
              in ((map['unenforced'] as Map?) ?? const <Object?, Object?>{}).entries)
            '${e.key}': '${e.value}',
        },
        fullscreen: map['fullscreen'] == true,
        confined: map['confined'] == true,
        notificationsSuppressed: map['notificationsSuppressed'] == true,
      );
}

class DVKiosk {
  DVKiosk._();

  static final StreamController<String> _blocked =
      StreamController<String>.broadcast();

  /// Every escape combo pressed and swallowed, as its accelerator text.
  static Stream<String> get blocked => _blocked.stream;

  /// For platform bindings: a grabbed combo was pressed.
  static void reportBlocked(String accelerator) => _blocked.add(accelerator);

  /// Holds [policy] on this device. Returns what was held; where the platform
  /// has no binding, nothing is, and the result says so rather than throwing,
  /// because DV-KIOSK-001 is the operator's finding to read, not a crash.
  static Future<DVKioskEnforced> enforce(DVKioskPolicy policy) async {
    final List<DVAccelerator> combos = DVKioskEscapeKeys.toBlock(policy);
    final Object? result = await DVNativeBridge.invoke<Object?>('kiosk.enforce', <String, Object?>{
      'combos': <String>[for (final DVAccelerator c in combos) c.canonical],
      'fullscreen': policy.fullscreen,
      // A kiosk keeps the pointer inside its window: input confinement, per
      // the enforcement table, wherever the platform can hold it.
      'confinePointer': policy.enabled,
      'suppressNotifications': policy.enabled,
    });
    if (result is Map) return DVKioskEnforced.fromMap(result);
    return DVKioskEnforced(
      blocked: const <String>[],
      unenforced: <String, String>{
        for (final DVAccelerator c in combos) c.canonical: 'no kiosk binding on this platform',
      },
    );
  }

  /// Lets go of everything [enforce] held.
  static Future<void> release() async {
    await DVNativeBridge.invoke<Object?>('kiosk.release');
  }
}
