/// What a target actually honours, as against what the policy asked for.
///
/// Kiosk is the one capability with no "present it another way" fallback --
/// there is no other way to lock a watch -- so the honest answer is a strength
/// label per target and a diagnostic whenever the answer is weaker than the
/// ask. A kiosk reporting success while the user can swipe out of it is worse
/// than one that says it cannot.
library dartvel.kiosk.enforcement;

import 'policy.dart';

/// How firmly a target can hold a kiosk.
enum DVKioskStrength {
  /// Nothing: the policy is off, or the target cannot do it at all.
  none,

  /// Fullscreen, and the user can still leave -- a browser reserves Esc.
  fullscreenOnly,

  /// Held, but with a documented way out the user may know.
  supervised,

  /// The OS prevents other applications from surfacing.
  device,
}

/// Whether input confinement covers a display or the whole device.
enum DVKioskInputScope { display, device }

/// The kiosk diagnostics, as the specification enumerates them.
enum DVKioskDegradation {
  none,
  enforcementReduced,
  exitWeaker,
  noPolicy,
  unsupportedTarget,
  routeBlocked,
  bindingMissing,
  lockedOut,
  inputScopeWidened,
}

/// The targets the specification gives a kiosk row.
enum DVKioskTarget {
  sonyELinux,
  androidDeviceOwner,
  androidScreenPinning,
  iPadOS,
  windows,
  macos,
  linuxDesktop,
  tizen,
  webos,
  web,
  browserExtension,
  watch,
  terminal,
}

extension DVKioskDegradationX on DVKioskDegradation {
  /// The stable code, or null when nothing degraded.
  String? get code => switch (this) {
        DVKioskDegradation.none => null,
        DVKioskDegradation.enforcementReduced => 'DV-KIOSK-001',
        DVKioskDegradation.exitWeaker => 'DV-KIOSK-002',
        DVKioskDegradation.lockedOut => 'DV-KIOSK-003',
        DVKioskDegradation.unsupportedTarget => 'DV-KIOSK-004',
        DVKioskDegradation.noPolicy => 'DV-KIOSK-005',
        DVKioskDegradation.routeBlocked => 'DV-KIOSK-006',
        DVKioskDegradation.bindingMissing => 'DV-KIOSK-007',
        DVKioskDegradation.inputScopeWidened => 'DV-KIOSK-010',
      };
}

/// What a device will actually do with a declared policy.
class DVKioskEnforcement {
  const DVKioskEnforcement({
    required this.strength,
    required this.inputScope,
    required this.exitMethod,
    required this.scopeHonoured,
    required this.supported,
    required this.degradations,
  });

  final DVKioskStrength strength;
  final DVKioskInputScope inputScope;

  /// The method that will actually be offered, which can be weaker than the
  /// declared one.
  final DVKioskExitMethod exitMethod;

  /// Whether `scope: display` is honoured, or degraded to a fullscreen page in
  /// the current surface.
  final bool scopeHonoured;

  /// Whether this target can be a kiosk at all.
  final bool supported;

  /// Everything worth saying at boot, most severe first.
  ///
  /// A list rather than one value, because these are independent facts and a
  /// target can be several at once: a supervised Android tablet running a
  /// display-scoped policy that blocks hardware keys is both reduced and
  /// widened. Collapsing to one loses whichever came second, and the second
  /// one is the one the staff terminal beside it will notice.
  final List<DVKioskDegradation> degradations;

  /// The most severe, for a caller that wants a single answer.
  DVKioskDegradation get degradation => degradations.isEmpty
      ? DVKioskDegradation.none
      : degradations.first;

  String? get code => degradation.code;

  /// Every code this enforcement reports.
  List<String> get codes => <String>[
        for (final DVKioskDegradation d in degradations)
          if (d.code != null) d.code!,
      ];

  /// The strongest a target can be, before the policy is taken into account.
  static DVKioskStrength ceilingFor(
    DVKioskTarget target, {
    bool browserKioskDetected = false,
  }) =>
      switch (target) {
        DVKioskTarget.sonyELinux ||
        DVKioskTarget.androidDeviceOwner ||
        DVKioskTarget.tizen ||
        DVKioskTarget.webos =>
          DVKioskStrength.device,
        // Exitable with a gesture the user may know.
        DVKioskTarget.androidScreenPinning ||
        DVKioskTarget.iPadOS ||
        DVKioskTarget.windows ||
        DVKioskTarget.linuxDesktop =>
          DVKioskStrength.supervised,
        // The browser reserves Esc; a dedicated kiosk mode is what raises it.
        DVKioskTarget.web => browserKioskDetected
            ? DVKioskStrength.device
            : DVKioskStrength.fullscreenOnly,
        DVKioskTarget.macos ||
        DVKioskTarget.terminal =>
          DVKioskStrength.fullscreenOnly,
        // Kiosk *is* the capability here, so there is no fallback.
        DVKioskTarget.browserExtension || DVKioskTarget.watch =>
          DVKioskStrength.none,
      };

  /// Resolves [policy] against what [target] can do.
  ///
  /// One degradation comes back, the most severe, so boot says a single thing.
  /// Being able to leave the kiosk matters more than an input-scope note, and
  /// reporting both would bury it.
  static DVKioskEnforcement resolve({
    required DVKioskPolicy policy,
    required DVKioskTarget target,
    bool displayKiosk = false,
    bool hasTouch = true,
    bool browserKioskDetected = false,
  }) {
    if (!policy.enabled) {
      return const DVKioskEnforcement(
        strength: DVKioskStrength.none,
        inputScope: DVKioskInputScope.device,
        exitMethod: DVKioskExitMethod.none,
        scopeHonoured: false,
        supported: false,
        degradations: <DVKioskDegradation>[DVKioskDegradation.noPolicy],
      );
    }

    final DVKioskStrength ceiling =
        ceilingFor(target, browserKioskDetected: browserKioskDetected);
    if (ceiling == DVKioskStrength.none) {
      return const DVKioskEnforcement(
        strength: DVKioskStrength.none,
        inputScope: DVKioskInputScope.device,
        exitMethod: DVKioskExitMethod.none,
        scopeHonoured: false,
        supported: false,
        degradations: <DVKioskDegradation>[
          DVKioskDegradation.unsupportedTarget,
        ],
      );
    }

    // display scope needs addressable displays; without them it becomes the
    // in-place fullscreen page.
    final bool wantsDisplay = policy.scope == DVKioskScope.display;
    final bool scopeHonoured = !wantsDisplay || displayKiosk;

    // A touchless device cannot take a corner-tap gesture.
    DVKioskExitMethod exitMethod = policy.exitMethod;
    final bool exitWeaker =
        exitMethod == DVKioskExitMethod.gesturePin && !hasTouch;
    if (exitWeaker) exitMethod = DVKioskExitMethod.pin;

    // A keyboard is a device and a touchscreen is a display: blocking hardware
    // keys for one display is not something an OS can do, so it is the whole
    // device -- which the staff terminal beside it will notice.
    final bool widened =
        wantsDisplay && scopeHonoured && policy.blockHardwareKeys;
    final DVKioskInputScope inputScope =
        wantsDisplay && scopeHonoured && !widened
            ? DVKioskInputScope.display
            : DVKioskInputScope.device;

    // Most severe first: being able to leave the kiosk matters more than a
    // weaker exit gesture, which matters more than an input-scope note.
    final List<DVKioskDegradation> degradations = <DVKioskDegradation>[
      if (ceiling != DVKioskStrength.device || !scopeHonoured)
        DVKioskDegradation.enforcementReduced,
      if (exitWeaker) DVKioskDegradation.exitWeaker,
      if (widened) DVKioskDegradation.inputScopeWidened,
    ];

    return DVKioskEnforcement(
      strength: ceiling,
      inputScope: inputScope,
      exitMethod: exitMethod,
      scopeHonoured: scopeHonoured,
      supported: true,
      degradations: degradations,
    );
  }
}
