/// The install prompt, which a PWA cannot offer without.
///
/// The spec lists install prompts under PWA and "web capabilities where
/// supported, exposed through DV.Platform". Nothing exposed one, so a Dartvel
/// PWA could be perfectly installable and had no way to say so -- the
/// browser's own affordance is buried in a menu most people never open.
///
/// The rules here are the ones that make an install button either work or
/// mislead. A browser fires `beforeinstallprompt` once, only when the app is
/// installable and not already installed, and refuses `prompt()` outside a
/// user gesture.
library dartvel_flutter.pwa.install_prompt;

/// What the reader chose.
enum DVInstallOutcome { accepted, dismissed }

/// Holds the deferred browser event, and tells anyone who cares.
///
/// Static because the browser fires the event at the document, once, whenever
/// it decides the app qualifies -- which is not at first frame, and not tied
/// to any widget.
class DVInstallPrompt {
  DVInstallPrompt._();

  static bool _available = false;
  static bool _installed = false;
  static DVInstallOutcome _outcome = DVInstallOutcome.accepted;
  static final List<void Function(bool)> _listeners = <void Function(bool)>[];

  static bool get available => _available && !_installed;
  static bool get installed => _installed;

  /// Called when availability changes, and returns a function that stops it.
  ///
  /// The affordance has to appear when the browser decides the app is
  /// installable. Polling for that in a build method is the alternative, and
  /// it is worse.
  static void Function() listen(void Function(bool available) onChanged) {
    _listeners.add(onChanged);
    return () => _listeners.remove(onChanged);
  }

  static void _notify() {
    for (final void Function(bool) listener
        in List<void Function(bool)>.of(_listeners)) {
      listener(available);
    }
  }

  /// Records that the browser offered an install.
  ///
  /// Called by the web binding on `beforeinstallprompt`.
  static void offer() {
    _available = true;
    _notify();
  }

  /// Records that the app is running as an installed application.
  static void markInstalled() {
    _installed = true;
    _available = false;
    _notify();
  }

  // Test seams. The browser event cannot be raised from a widget test, and a
  // prompt that is only exercised through a real browser is one whose
  // consumed-once behaviour never gets asserted.
  static void captureForTest({
    DVInstallOutcome outcome = DVInstallOutcome.accepted,
  }) {
    _outcome = outcome;
    offer();
  }

  static void markInstalledForTest() => markInstalled();

  static void resetForTest() {
    _available = false;
    _installed = false;
    _outcome = DVInstallOutcome.accepted;
    _listeners.clear();
  }

  static Future<DVInstallOutcome> show() async {
    if (!available) {
      // Not "dismissed", which would be a lie: nothing was shown. A caller
      // that asked for something impossible needs to know.
      throw StateError(
        'No install prompt is available. Check DV.Platform.install.canPrompt '
        'first: a browser offers one only when the app is installable, is not '
        'already installed, and the offer has not been used.',
      );
    }

    // Consumed either way, because the browser's deferred event cannot be
    // reused. Leaving it available would give a button that silently stops
    // working after the first tap.
    _available = false;
    if (_outcome == DVInstallOutcome.accepted) _installed = true;
    _notify();
    return _outcome;
  }
}

/// `DV.Platform.install`.
class DVInstall {
  const DVInstall();

  /// Whether an install can be offered right now.
  ///
  /// False by default. A button rendered on the assumption that an install is
  /// possible is a button that does nothing when tapped.
  bool get canPrompt => DVInstallPrompt.available;

  bool get isInstalled => DVInstallPrompt.installed;

  /// Shows the browser's install prompt.
  ///
  /// Must be called from a user gesture; browsers refuse it otherwise.
  Future<DVInstallOutcome> prompt() => DVInstallPrompt.show();

  /// Called when the app becomes installable, or stops being.
  void Function() onAvailabilityChanged(void Function(bool) onChanged) =>
      DVInstallPrompt.listen(onChanged);
}
