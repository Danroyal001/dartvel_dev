import 'dart:async';
import 'dart:ui' as ui show Display;

import 'package:dartvel_core/dartvel.dart' show DVDiagnostics, DVInstanceLock;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// What a target can actually do with windows.
///
/// Read this to decide whether to *offer* an affordance. Never to decide
/// whether to call [DVWindowManager.open] — that always presents the route,
/// which is the whole point of a window being one.
class DVWindowingCapability {
  /// Whether a second OS-level window can exist at all.
  final bool multiWindow;

  /// Whether windows share one engine, so content can be handed over as the
  /// same Dart object tree rather than through the shared store.
  final bool sameEngine;

  /// Whether a tab can detach into a window by drag.
  final bool tearOut;

  /// Web only: in-page multi-view embedding for panels and workspace regions.
  final bool inPageViews;

  /// Whether the OS supports blocking every window of the application.
  final bool applicationModal;

  /// Whether more than one display is addressable.
  ///
  /// Unlike the others this changes while the process runs -- a display is
  /// plugged in or unplugged -- so it is read from the current display list
  /// rather than detected once at start. A workspace hides its "move to
  /// display" control on the strength of it.
  final bool displays;

  const DVWindowingCapability({
    this.multiWindow = false,
    this.sameEngine = false,
    this.tearOut = false,
    this.inPageViews = false,
    this.applicationModal = false,
    this.displays = false,
  });

  /// What a desktop host reports once real windowing is available.
  ///
  /// A named thing rather than four booleans at a call site: the combination
  /// that means "desktop" is not obvious from the flags, and a test that spelt
  /// it out would go stale the day the combination changed.
  ///
  /// [displays] is deliberately not set here. It is the one capability that
  /// changes while the process runs, and it is read from the live display list
  /// -- freezing it into a fake would make a "move to display" control
  /// untestable.
  factory DVWindowingCapability.desktop() => const DVWindowingCapability(
        multiWindow: true,
        sameEngine: true,
        tearOut: true,
      );

  /// This capability with [displays] recomputed from a display count.
  DVWindowingCapability withDisplayCount(int count) => DVWindowingCapability(
        multiWindow: multiWindow,
        sameEngine: sameEngine,
        tearOut: tearOut,
        inPageViews: inPageViews,
        applicationModal: applicationModal,
        displays: count > 1,
      );

  /// The capability of the running target.
  ///
  /// Desktop reports `multiWindow` only when the `window.open` binding is
  /// registered: Flutter's desktop windowing is experimental and behind a
  /// flag, so claiming the capability before the binding exists would be a
  /// promise the next call breaks.
  static DVWindowingCapability detect({
    required bool isDesktop,
    required bool isWeb,
    required bool isAndroid,
    required bool isTablet,
    required bool isIOS,
    required bool hasNativeWindowBinding,
    bool kioskLocked = false,
    bool enabledByConfig = true,
  }) {
    if (!enabledByConfig || kioskLocked) return const DVWindowingCapability();
    if (isDesktop) {
      return DVWindowingCapability(
        multiWindow: hasNativeWindowBinding,
        sameEngine: hasNativeWindowBinding,
        tearOut: hasNativeWindowBinding,
      );
    }
    if (isWeb) {
      // Tear-out by drag is false: a drag ending on the desktop cannot open a
      // popup, because the call is no longer attributed to a user gesture.
      // Web gets the explicit affordance instead.
      return const DVWindowingCapability(
        multiWindow: true,
        sameEngine: false,
        tearOut: false,
        inPageViews: true,
      );
    }
    if (isAndroid) {
      return const DVWindowingCapability(multiWindow: true);
    }
    // iPadOS scenes; an iPhone has no second scene to give.
    if (isIOS && isTablet) {
      return const DVWindowingCapability(multiWindow: true, tearOut: true);
    }
    return const DVWindowingCapability();
  }
}

/// What kind of surface was asked for.
enum DVWindowKind { regular, dialog, popup, tooltip, satellite }

extension DVWindowKindX on DVWindowKind {
  /// Whether this kind counts towards the exit policy and can be `main`.
  ///
  /// Owned kinds -- dialog, popup, tooltip, satellite -- do not. One of them
  /// anchoring restore would put a restored workspace inside a dialog, and a
  /// lingering tooltip would hold an application open with nothing on screen.
  ///
  /// The specification says "regular or kiosk"; the kiosk kind is not built
  /// yet, so regular is the whole set today.
  bool get countsAsPrincipal => this == DVWindowKind.regular;

  /// Whether this kind belongs to another window.
  bool get isOwned => this != DVWindowKind.regular;

  /// What this kind blocks when nothing is asked for.
  DVWindowModality get defaultModality => this == DVWindowKind.dialog
      ? DVWindowModality.window
      : DVWindowModality.none;
}

/// What a window blocks while it is open.
enum DVWindowModality {
  /// Blocks nothing.
  none,

  /// Blocks input to the owner only. The default for a dialog.
  window,

  /// Blocks every window of the application, where the OS can.
  application,
}

/// When closing a window ends the process.
enum DVWindowExitPolicy {
  /// The last regular window closing ends it. The desktop default.
  lastWindow,

  /// `main` closing ends it, whatever else is open.
  mainWindow,

  /// Nothing on a window close ends it -- tray-resident applications.
  explicit,
}

/// How the request was actually presented.
enum DVWindowPresentation { window, page, dialog, overlay }

/// Why a request was presented as something other than a window.
enum DVWindowDegradation {
  none,
  capabilityUnsupported,
  kioskLocked,
  gestureRequired,
  platformRefused,
  disabledByConfig,
  displayUnavailable,
  restoredRouteUnresolvable,
  ownerClosed,
  modalityReduced,
}

extension DVWindowDegradationX on DVWindowDegradation {
  /// The stable diagnostic code, or null when nothing degraded.
  ///
  /// Codes never change meaning between releases; `dartvel explain` reads
  /// them.
  String? get code => switch (this) {
        DVWindowDegradation.none => null,
        DVWindowDegradation.capabilityUnsupported => 'DV-WINDOW-001',
        DVWindowDegradation.kioskLocked => 'DV-WINDOW-002',
        DVWindowDegradation.gestureRequired => 'DV-WINDOW-003',
        DVWindowDegradation.platformRefused => 'DV-WINDOW-004',
        DVWindowDegradation.disabledByConfig => 'DV-WINDOW-005',
        DVWindowDegradation.displayUnavailable => 'DV-WINDOW-013',
        DVWindowDegradation.restoredRouteUnresolvable => 'DV-WINDOW-009',
        DVWindowDegradation.ownerClosed => 'DV-WINDOW-007',
        DVWindowDegradation.modalityReduced => 'DV-WINDOW-008',
      };

  /// The level the specification assigns this code.
  ///
  /// Read from the registry rather than restated here. It used to be a second
  /// hand-written switch, and a second copy of a published contract drifts:
  /// this one had DV-WINDOW-006 at `warning` while the specification had it at
  /// `error`, and nothing compared them.
  ///
  /// Calibrated to whether the developer can act on it. A phone has no windows
  /// and the fallback is intended, so warning on every call would train people
  /// to ignore the channel.
  String get level =>
      code == null ? 'debug' : DVDiagnostics.find(code!)?.level ?? 'warning';

  /// What happened, in the specification's own words.
  String get reason => code == null
      ? 'a window was created'
      : DVDiagnostics.find(code!)?.reason ?? 'the window request degraded';
}

/// The lifecycle of a window, as a read-only signal the runtime owns.
enum DVWindowLifecycle {
  requested,
  creating,
  created,
  ready,
  active,
  inactive,
  minimized,
  maximized,
  fullscreen,
  closing,
  closed,
  failed,
}

class DVWindowOptions {
  final Size? size;
  final BoxConstraints? constraints;
  final String? title;
  final DVWindowKind kind;

  /// Opening a route a window already shows focuses that window. Pass true
  /// for a deliberate second window on the same route.
  final bool duplicate;

  /// Which display to open on.
  ///
  /// Which display, never where on it: the OS places the window, and an
  /// application that positioned windows by coordinate would be wrong the
  /// moment a monitor was rearranged.
  final DVDisplayHint? display;

  /// The window this one belongs to.
  ///
  /// Required for the owned kinds. An owned window cannot outlive its owner,
  /// so it has to have one.
  final DVWindow? owner;

  /// What this window blocks while open. Null takes the kind's default.
  final DVWindowModality? modality;

  /// Whether this request came from the OS rather than from the application.
  ///
  /// Named `isExternal` on the instance so the const value below can be
  /// `DVWindowOptions.external`, which is what the specification writes at a
  /// call site and the only one of the two names anybody types.
  final bool isExternal;

  const DVWindowOptions({
    this.size,
    this.constraints,
    this.title,
    this.kind = DVWindowKind.regular,
    this.duplicate = false,
    this.display,
    this.owner,
    this.modality,
    this.isExternal = false,
  });

  /// An OS-delivered open request.
  ///
  /// The contract routes a deep link, a file association and a second launch
  /// through the same idempotent open() as everything else, so a link to an
  /// order already on screen focuses that window rather than opening another.
  static const DVWindowOptions external = DVWindowOptions(isExternal: true);
}

/// A window, real or virtual.
///
/// The same handle either way: `close()` closes a window or pops a route, and
/// [DVWindowManager.all] lists both, so a tab strip or a close-all command is
/// written once and works on a phone.
class DVWindow {
  final DVRouteTarget route;
  final DVWindowKind kind;
  final DVWindowPresentation presentation;
  final DVWindowDegradation degradation;

  /// The native handle, when one exists.
  final String? nativeId;

  /// The window this one belongs to, for an owned kind that got a live owner.
  final DVWindow? owner;

  /// What this window blocks while it is open.
  final DVWindowModality modality;

  /// Whether the OS handed this route over rather than the application asking.
  ///
  /// A deep link, a file association, a `dartvel://` URL, a second launch of a
  /// single-instance application. A route the user navigated to and a route
  /// the OS delivered are not the same event, and a policy or an analytic that
  /// cannot tell them apart reports every deep link as navigation.
  final bool external;

  DVWindow({
    required this.route,
    required this.kind,
    required this.presentation,
    this.degradation = DVWindowDegradation.none,
    this.nativeId,
    this.owner,
    this.modality = DVWindowModality.none,
    this.external = false,
  });

  final ValueNotifier<DVWindowLifecycle> _lifecycle =
      ValueNotifier<DVWindowLifecycle>(DVWindowLifecycle.requested);

  /// Observed, never assigned: the runtime owns transitions.
  ValueListenable<DVWindowLifecycle> get lifecycle => _lifecycle;

  /// True when the route was navigated rather than windowed.
  bool get isVirtual => presentation != DVWindowPresentation.window;

  void setLifecycle(DVWindowLifecycle value) => _lifecycle.value = value;

  /// A no-op on a virtual window, logged rather than vanishing.
  Future<void> setSize(Size size) async {
    if (isVirtual) {
      await _logIgnored('setSize');
      return;
    }
    await DVNativeBridge.require<bool>('window.setSize', <String, Object?>{
      'id': nativeId,
      'width': size.width,
      'height': size.height,
    });
  }

  /// Maps to the page title on a virtual window, which is the closest true
  /// equivalent rather than a discard.
  Future<void> setTitle(String title) async {
    await DVNativeBridge.invoke<bool>('window.setTitle', <String, Object?>{
      'id': nativeId,
      'title': title,
    });
  }

  Future<void> close() async {
    _lifecycle.value = DVWindowLifecycle.closing;

    // Owned windows go first, and in reverse open order: the last opened is
    // closest to the user, so a palette disappearing before the dialog sitting
    // on top of it would flash the wrong thing. An owned window cannot outlive
    // its owner.
    for (final DVWindow owned in DVWindowManager.ownedBy(this).reversed) {
      await owned.close();
    }
    if (!isVirtual) {
      await DVNativeBridge.invoke<bool>(
        'window.close',
        <String, Object?>{'id': nativeId},
      );
    }
    _lifecycle.value = DVWindowLifecycle.closed;
    DVWindowManager.forget(this);
  }

  Future<void> _logIgnored(String call) async {
    try {
      await _emitIgnored(call);
    } catch (_) {
      // A call that does nothing must not start failing because telemetry is
      // unconfigured; see DVWindowManager._report.
    }
  }

  Future<void> _emitIgnored(String call) => DV.log(
        'DV-WINDOW-001  $call ignored on a virtual window.',
        level: 'debug',
        context: <String, Object>{
          'route': route.path,
          'presentation': presentation.name,
          'call': call,
        },
      );
}

/// The window manager.
///
/// `DV.Platform.Window` and its `DV.Window` alias resolve here. The
/// current-window members it already had — `setTitle`, `persistState`,
/// `restoreState` — remain, now as sugar over [current].
class DVWindowManager {
  final DVPlatform _platform;
  const DVWindowManager(this._platform);

  static final List<DVWindow> _windows = <DVWindow>[];
  static final ValueNotifier<List<DVWindow>> _all =
      ValueNotifier<List<DVWindow>>(<DVWindow>[]);

  /// When a window close ends the process.
  ///
  /// A no-op on targets with no process to exit in this sense -- web, Android
  /// tasks, iPadOS scenes -- where nothing reads [shouldExit].
  static DVWindowExitPolicy exitPolicy = DVWindowExitPolicy.lastWindow;

  static final ValueNotifier<DVWindow?> _main =
      ValueNotifier<DVWindow?>(null);
  static final ValueNotifier<bool> _shouldExit = ValueNotifier<bool>(false);

  static final ValueNotifier<List<DVDisplay>> _displays =
      ValueNotifier<List<DVDisplay>>(const <DVDisplay>[]);

  /// A device profile's `displays:` map: a name against the position it names.
  ///
  /// The shape the specification fixes, `displays: { Customer: { index: 1 } }`.
  /// Kiosk deployments address displays by role -- `byName('Customer')` -- and
  /// the OS name is whatever the panel's EDID says.
  ///
  /// Nothing populates this from configuration yet; a device profile's
  /// displays are not carried into the generated client. Until they are, an
  /// application that wants profile names sets this itself.
  static Map<String, int> displayProfile = const <String, int>{};

  /// The routes this application actually has, for validating a restored
  /// workspace.
  ///
  /// Empty means "not known", and restore then keeps everything it stored:
  /// nothing has told the runtime which routes exist, so dropping tabs on a
  /// guess would lose a workspace. The generated router is what fills this.
  static Set<String> knownRoutes = const <String>{};

  /// Overridden capability, for tests and for configuration that disables
  /// windowing. Null means detect from the running target.
  static DVWindowingCapability? _capabilityOverride;

  static set capabilityOverride(DVWindowingCapability? value) {
    _capabilityOverride = value;
  }

  /// Clears every window and any override. Tests use this so one test cannot
  /// see another's windows.
  static void reset() {
    _windows.clear();
    _all.value = <DVWindow>[];
    _displays.value = const <DVDisplay>[];
    displayProfile = const <String, int>{};
    knownRoutes = const <String>{};
    _main.value = null;
    _shouldExit.value = false;
    exitPolicy = DVWindowExitPolicy.lastWindow;
    _capabilityOverride = null;
    _shared = null;
  }

  /// The windows [owner] owns, in the order they were opened.
  static List<DVWindow> ownedBy(DVWindow owner) => <DVWindow>[
        for (final DVWindow window in _windows)
          if (identical(window.owner, owner)) window,
      ];

  static void forget(DVWindow window) {
    final bool wasMain = identical(_main.value, window);
    _windows.remove(window);
    _all.value = List<DVWindow>.unmodifiable(_windows);

    // Promotion before the exit decision: under exit: mainWindow the answer
    // depends on whether the window that closed was main, and after promotion
    // it no longer is.
    if (wasMain) _promoteMain();

    final bool exits = switch (exitPolicy) {
      DVWindowExitPolicy.explicit => false,
      DVWindowExitPolicy.mainWindow => wasMain,
      DVWindowExitPolicy.lastWindow =>
        !_windows.any((DVWindow w) => w.kind.countsAsPrincipal),
    };
    // Latched, not recomputed. Under mainWindow, closing main decides the
    // process should end, and a stray window closing afterwards would compute
    // false and cancel an exit the embedder had not got round to acting on --
    // so nothing would ever exit. Only opening a window clears it, because
    // then there is something on screen again.
    if (exits) _shouldExit.value = true;
  }

  /// The oldest remaining principal window, or none.
  static void _promoteMain() {
    for (final DVWindow window in _windows) {
      if (window.kind.countsAsPrincipal) {
        _main.value = window;
        return;
      }
    }
    _main.value = null;
  }

  /// Every window, virtual ones included.
  ValueListenable<List<DVWindow>> get all => _all;

  /// The window this code is running in.
  DVWindow? get current => _windows.isEmpty ? null : _windows.first;

  /// The main window: the first principal window opened, and the anchor for
  /// restore and for deep links with no target.
  ///
  /// Signal-backed because it is promoted. Code that read it once would keep a
  /// handle to a closed window.
  ValueListenable<DVWindow?> get main => _main;

  /// Whether the last window close means the process should end.
  ///
  /// A signal rather than a call to exit: whether and how to end a process is
  /// the embedder's business, and on targets with no process to exit in this
  /// sense nothing reads it.
  ValueListenable<bool> get shouldExit => _shouldExit;

  /// Every display the application knows of.
  ///
  /// Empty until [refreshDisplays] has run: enumeration touches a native
  /// binding, so it is not done in a getter.
  ValueListenable<List<DVDisplay>> get displays => _displays;

  /// Re-reads the display list and publishes it to [displays].
  ///
  /// Prefers the `window.displays` native binding, which reports what the OS
  /// knows -- layout origins, panel names, which display is primary. Without
  /// it, Flutter's own `PlatformDispatcher.displays` still gives size, pixel
  /// ratio and refresh rate for every display, and unlike the desktop
  /// windowing API it is stable rather than behind an experimental flag. What
  /// it cannot give is where the displays sit relative to each other, which
  /// [DVDisplay.hasLayout] reports rather than invents.
  ///
  /// Never throws. Failing to enumerate displays should cost the display list,
  /// not the launch.
  Future<List<DVDisplay>> refreshDisplays() async {
    List<DVDisplay> found = const <DVDisplay>[];
    try {
      final Object? payload = DVNativeBridge.isRegistered('window.displays')
          ? await DVNativeBridge.invoke<Object?>('window.displays')
          : _flutterDisplays();
      found = DVDisplays.decode(payload, profile: displayProfile);
    } on Object {
      found = const <DVDisplay>[];
    }
    _displays.value = List<DVDisplay>.unmodifiable(found);
    return _displays.value;
  }

  /// Flutter's display list, as the same payload shape a binding returns.
  ///
  /// No `left`/`top`: Flutter reports no layout origin, and the decoder marks
  /// the difference rather than defaulting every display to the same corner.
  static List<Object?> _flutterDisplays() => <Object?>[
        for (final ui.Display display
            in WidgetsBinding.instance.platformDispatcher.displays)
          <String, Object?>{
            'id': '${display.id}',
            'width': display.size.width,
            'height': display.size.height,
            'devicePixelRatio': display.devicePixelRatio,
            'refreshRate': display.refreshRate,
          },
      ];

  DVWindowingCapability get capability => _detectCapability()
      .withDisplayCount(_displays.value.length);

  DVWindowingCapability _detectCapability() =>
      _capabilityOverride ??
      DVWindowingCapability.detect(
        isDesktop: _platform.isLinux || _platform.isMacOS || _platform.isWindows,
        isWeb: _platform.isWeb,
        isAndroid: _platform.isAndroid,
        isTablet: _platform.type == 'tablet',
        isIOS: _platform.isIOS,
        hasNativeWindowBinding: DVNativeBridge.isRegistered('window.open'),
      );

  static DVWindowSharedStore? _shared;

  /// Cross-window view state. One API on every platform; what varies is
  /// whether the OS delivers the notification or a shared isolate does.
  static DVWindowSharedStore get shared =>
      _shared ??= DVWindowSharedStore();

  /// Replaces the store, for tests and for targets that register a
  /// preference-backed backend.
  static void useSharedStore(DVWindowSharedStore store) {
    _shared = store;
  }

  /// Opens whatever a second launch asked for, and clears the queue.
  ///
  /// The single-instance lock refuses the second process and queues the route
  /// it was launched with; this is the other half. Without it the queue filled
  /// and was never read, so a deep link, a file association or a second launch
  /// reached a process that then exited and the running application never
  /// heard about it.
  ///
  /// Goes through the same [open] as everything else, so it is idempotent by
  /// URL: a link to an order already on screen focuses that window rather than
  /// opening a second one.
  ///
  /// Returns how many routes were opened. Only the primary instance has a
  /// queue to drain -- a secondary that drained would swallow the route it
  /// just asked for -- so calling this on one is a no-op rather than an error.
  Future<int> drainExternalOpens(DVInstanceLock lock) async {
    var opened = 0;
    for (final String route in lock.takePending()) {
      // Written by another process, so it is not trusted input. Opening
      // whatever it says would let a second launch name any route at all.
      final String path = route.trim();
      if (path.isEmpty || !path.startsWith('/')) continue;

      await open(DVRouteTarget(path), options: DVWindowOptions.external);
      opened += 1;
    }
    return opened;
  }

  Rect get bounds =>
      Offset.zero & Size(_platform.screenWidth, _platform.screenHeight);

  /// Opens [route] in a window, or presents it the way this target can.
  ///
  /// Never fails. Where a window cannot be created the route is navigated
  /// instead, and the reason is reported — a degradation nobody can see is
  /// the silent-ignoring the specification forbids.
  ///
  /// Idempotent by route: opening a route a window already shows returns that
  /// window rather than duplicating it, unless `options.duplicate` is set.
  Future<DVWindow> open(
    DVRouteTarget route, {
    DVWindowOptions options = const DVWindowOptions(),
  }) async {
    if (!options.duplicate) {
      for (final existing in _windows) {
        if (existing.route.path == route.path) return existing;
      }
    }

    final cap = capability;
    DVWindowDegradation degradation = DVWindowDegradation.none;
    String? nativeId;

    // Resolved before the platform call, because the display id goes with it.
    // Enumerate first when a hint was given and nothing has yet, or the first
    // window of the process would always land on the primary display.
    DVDisplayResolution? display;
    if (options.display != null) {
      if (_displays.value.isEmpty) await refreshDisplays();
      display = DVDisplays.resolve(_displays.value, options.display);
    }

    // An owned kind naming an owner that has already closed is refused rather
    // than reparented. Adopting main would put a dialog on a window the user
    // was not working in, and block input there.
    final DVWindow? requestedOwner =
        options.kind.isOwned ? options.owner : null;
    final bool ownerGone = requestedOwner != null &&
        !_windows.contains(requestedOwner);

    // Application modality is honoured only where the OS can enforce it. A
    // fake application-modal that leaks input is worse than an honest
    // window-modal: the user finds the gap, and the thing meant to be blocked
    // happens anyway.
    DVWindowModality modality =
        options.modality ?? options.kind.defaultModality;
    final bool modalityReduced =
        modality == DVWindowModality.application && !cap.applicationModal;
    if (modalityReduced) modality = DVWindowModality.window;

    if (ownerGone) {
      degradation = DVWindowDegradation.ownerClosed;
    } else if (!cap.multiWindow) {
      degradation = DVWindowDegradation.capabilityUnsupported;
    } else {
      try {
        nativeId = await DVNativeBridge.invoke<String>(
          'window.open',
          <String, Object?>{
            'route': route.path,
            'kind': options.kind.name,
            'title': options.title,
            'width': options.size?.width,
            'height': options.size?.height,
            if (display?.display != null) 'displayId': display!.display!.id,
          },
        );
        if (nativeId == null) {
          degradation = DVWindowDegradation.platformRefused;
        }
      } catch (_) {
        degradation = DVWindowDegradation.platformRefused;
      }
    }

    // Only when nothing worse happened: a window that could not be created at
    // all is the more useful report, and "it opened on the wrong screen" would
    // be untrue as well as less severe.
    if (degradation == DVWindowDegradation.none && display?.exact == false) {
      degradation = display!.degradation;
    }
    // Quieter still than the display one: nothing was blocked that the
    // platform could have blocked.
    if (degradation == DVWindowDegradation.none && modalityReduced) {
      degradation = DVWindowDegradation.modalityReduced;
    }

    final presentation = degradation == DVWindowDegradation.none ||
            degradation == DVWindowDegradation.displayUnavailable ||
            degradation == DVWindowDegradation.modalityReduced
        ? DVWindowPresentation.window
        : _presentationFor(options.kind);

    final window = DVWindow(
      route: route,
      kind: options.kind,
      presentation: presentation,
      degradation: degradation,
      nativeId: nativeId,
      owner: ownerGone ? null : requestedOwner,
      modality: modality,
      external: options.isExternal,
    );
    _windows.add(window);
    _all.value = List<DVWindow>.unmodifiable(_windows);

    // The first principal window is main. An owned window opened first -- a
    // dialog before anything else -- leaves main unset rather than becoming
    // it, or a restored workspace would land inside a dialog.
    if (_main.value == null && window.kind.countsAsPrincipal) {
      _main.value = window;
    }
    // Opening a window undoes a previous "the last one closed".
    if (_shouldExit.value) _shouldExit.value = false;

    if (degradation != DVWindowDegradation.none) {
      await _report(window, degradation, options.kind);
      if (DV.Navigation.isAttached) DV.Navigation.navigate(route);
    }

    window.setLifecycle(DVWindowLifecycle.ready);
    return window;
  }

  /// A kind that cannot be a window becomes the nearest thing the platform
  /// can present, so the fallback is the same content rather than a
  /// consolation prize.
  static DVWindowPresentation _presentationFor(DVWindowKind kind) =>
      switch (kind) {
        DVWindowKind.regular => DVWindowPresentation.page,
        DVWindowKind.dialog => DVWindowPresentation.dialog,
        DVWindowKind.popup ||
        DVWindowKind.tooltip ||
        DVWindowKind.satellite =>
          DVWindowPresentation.overlay,
      };

  /// Reports a degradation without being able to cause one.
  ///
  /// `open()` never fails, and that has to survive an application with no
  /// observability configured — otherwise the contract holds only where
  /// telemetry happens to be wired, which is not a contract. A report that
  /// cannot be delivered is not a silent ignore either: the degradation stays
  /// readable on the returned window, which is the caller's own channel.
  static Future<void> _report(
    DVWindow window,
    DVWindowDegradation degradation,
    DVWindowKind requested,
  ) async {
    try {
      await _emit(window, degradation, requested);
    } catch (_) {
      // Deliberately swallowed; see above.
    }
  }

  static Future<void> _emit(
    DVWindow window,
    DVWindowDegradation degradation,
    DVWindowKind requested,
  ) =>
      DV.log(
        '${degradation.code}  Window request presented as '
        '${window.presentation.name}.',
        level: degradation.level,
        context: <String, Object>{
          'route': window.route.path,
          'requested': requested.name,
          'presented': window.presentation.name,
          'reason': degradation.reason,
        },
      );

  /// Saves the current window and tab layout under [name].
  ///
  /// Stored as view state through the shared store rather than a native
  /// window API, because the layout has to come back on a target that has no
  /// windows at all — a phone reopening its tabs is the same feature.
  Future<void> persistWorkspace(
    String name, {
    List<DVTabWorkspaceController> workspaces =
        const <DVTabWorkspaceController>[],
  }) async {
    final layout = <DVJsonValue>[
      for (final workspace in workspaces)
        DVJsonMap(<String, DVJsonValue>{
          'active': DVJsonNumber(workspace.activeIndex),
          'tabs': DVJsonList(<DVJsonValue>[
            for (final tab in workspace.tabs) DVJsonString(tab.route.path),
          ]),
        }),
    ];
    await shared.setReserved(_workspaceKey(name), DVJsonList(layout));
    await shared.flushReserved(_workspaceKey(name));
  }

  /// Restores what [persistWorkspace] saved, or an empty list when nothing is
  /// stored — a first launch is not a failure.
  Future<List<DVTabWorkspaceController>> restoreWorkspace(String name) async {
    final stored = await shared.getReserved(_workspaceKey(name));
    if (stored is! DVJsonList) return <DVTabWorkspaceController>[];

    final restored = <DVTabWorkspaceController>[];
    final dropped = <String>[];

    for (final entry in stored.value) {
      if (entry is! DVJsonMap) continue;
      final tabs = entry.value['tabs'];
      if (tabs is! DVJsonList) continue;

      // Kept paths and their old positions together, because the stored active
      // index counts the tabs that were saved. Dropping one before it and
      // keeping the number selects a different tab -- silently, since it is
      // still a valid index.
      final kept = <String>[];
      final oldIndexOf = <int>[];
      for (var i = 0; i < tabs.value.length; i++) {
        final path = tabs.value[i];
        if (path is! DVJsonString) continue;
        if (knownRoutes.isNotEmpty && !knownRoutes.contains(path.value)) {
          dropped.add(path.value);
          continue;
        }
        kept.add(path.value);
        oldIndexOf.add(i);
      }

      // Only when dropping emptied it. A workspace that was saved with no
      // tabs is a real empty workspace and comes back as one; a workspace
      // whose every route has since gone comes back not at all, because an
      // empty one there looks like the user closed everything themselves.
      if (kept.isEmpty && tabs.value.isNotEmpty) continue;

      final controller = DVTabWorkspaceController(
        tabs: <DVTab>[for (final String path in kept) DVTab(DVRouteTarget(path))],
      );

      final active = entry.value['active'];
      if (active is DVJsonNumber) {
        final int wanted = active.value.toInt();
        var index = oldIndexOf.indexOf(wanted);
        // The tab that was active is gone, so the nearest surviving one.
        if (index < 0) {
          index = oldIndexOf.where((int old) => old < wanted).length;
          if (index >= kept.length) index = kept.length - 1;
        }
        controller.activate(index);
      }
      restored.add(controller);
    }

    if (dropped.isNotEmpty) {
      // info, not a warning: a page removed between releases is normal, and
      // the workspace comes back without it rather than not coming back.
      await _reportRestoreDrop(name, dropped);
    }
    return restored;
  }

  Future<void> _reportRestoreDrop(String name, List<String> dropped) async {
    const DVWindowDegradation degradation =
        DVWindowDegradation.restoredRouteUnresolvable;
    try {
      await DV.log(
        '${degradation.code}  ${dropped.length} restored route(s) no longer '
        'resolve; the workspace came back without them.',
        level: degradation.level,
        context: <String, Object>{
          'workspace': name,
          'routes': dropped.join(', '),
          'reason': degradation.reason,
        },
      );
    } catch (_) {
      // Same reason open() swallows its own: a restore must not fail because
      // an application has no observability wired.
    }
  }

  /// Tenant- and user-scoped like any stored state; the store applies that
  /// scoping, so the key only distinguishes one workspace from another.
  static String _workspaceKey(String name) => 'workspace.layout.$name';

  Future<void> setTitle(String title) async {
    await DVNativeBridge.require<bool>('window.setTitle', {'title': title});
  }

  Future<void> maximize() async {
    await DVNativeBridge.require<bool>('window.maximize');
  }

  Future<void> minimize() async {
    await DVNativeBridge.require<bool>('window.minimize');
  }

  Future<void> restore() async {
    await DVNativeBridge.require<bool>('window.restore');
  }

  /// Remembers this window's size under [key].
  ///
  /// Composed rather than bound. `window.persistState` was on the list of names
  /// to implement natively on every platform, and it does not need to be:
  /// Flutter knows its own window size, and the shared store already keeps
  /// state between runs. Binding it would have meant writing the same logic
  /// five times against five different preference APIs.
  Future<void> persistState(String key) async {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final ratio = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    final state = DVWindowState(
      width: (view.physicalSize.width / ratio).round(),
      height: (view.physicalSize.height / ratio).round(),
    );
    await shared.setReserved(
        dvWindowStateKey(key), DVJsonString(state.encode()));
    await shared.flushReserved(dvWindowStateKey(key));
  }

  /// Puts back what [persistState] recorded.
  ///
  /// Silent when there is nothing stored, when the stored value is unusable, or
  /// when this platform cannot resize its own window. None of those is an
  /// error: a first launch has nothing to restore, a stale preference should
  /// not break startup, and macOS deliberately leaves `window.setSize` unbound
  /// because it needs the main thread.
  ///
  /// `invoke` rather than `require`, so an unbound platform declines instead of
  /// throwing at an application that only asked to be tidy.
  Future<void> restoreState(String key) async {
    final stored = await shared.getReserved(dvWindowStateKey(key));
    if (stored is! DVJsonString) return;

    final state = DVWindowState.decode(stored.value);
    if (state == null) return;

    await DVNativeBridge.invoke<bool>('window.setSize', <String, Object?>{
      'width': state.width,
      'height': state.height,
    });
  }
}
