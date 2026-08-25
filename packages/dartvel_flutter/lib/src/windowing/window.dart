import 'dart:async';

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

  const DVWindowingCapability({
    this.multiWindow = false,
    this.sameEngine = false,
    this.tearOut = false,
    this.inPageViews = false,
  });

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
      };

  /// Calibrated to whether the developer can act on it. A phone has no
  /// windows and the fallback is intended, so warning on every call would
  /// train people to ignore the channel.
  String get level => switch (this) {
        DVWindowDegradation.none => 'debug',
        DVWindowDegradation.capabilityUnsupported => 'debug',
        DVWindowDegradation.kioskLocked => 'info',
        DVWindowDegradation.disabledByConfig => 'info',
        DVWindowDegradation.gestureRequired => 'warning',
        DVWindowDegradation.platformRefused => 'warning',
      };

  String get reason => switch (this) {
        DVWindowDegradation.none => 'a window was created',
        DVWindowDegradation.capabilityUnsupported =>
          'this target has no multi-window capability',
        DVWindowDegradation.kioskLocked =>
          'kiosk mode is active; the surface stays locked',
        DVWindowDegradation.gestureRequired =>
          'web popup blocked — open() was not called during a user gesture',
        DVWindowDegradation.platformRefused =>
          'the platform refused the request',
        DVWindowDegradation.disabledByConfig =>
          'windowing.enabled is false in configuration',
      };
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

  const DVWindowOptions({
    this.size,
    this.constraints,
    this.title,
    this.kind = DVWindowKind.regular,
    this.duplicate = false,
  });
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

  DVWindow({
    required this.route,
    required this.kind,
    required this.presentation,
    this.degradation = DVWindowDegradation.none,
    this.nativeId,
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
    _capabilityOverride = null;
    _shared = null;
  }

  static void forget(DVWindow window) {
    _windows.remove(window);
    _all.value = List<DVWindow>.unmodifiable(_windows);
  }

  /// Every window, virtual ones included.
  ValueListenable<List<DVWindow>> get all => _all;

  /// The window this code is running in.
  DVWindow? get current => _windows.isEmpty ? null : _windows.first;

  DVWindowingCapability get capability =>
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

    if (!cap.multiWindow) {
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
          },
        );
        if (nativeId == null) {
          degradation = DVWindowDegradation.platformRefused;
        }
      } catch (_) {
        degradation = DVWindowDegradation.platformRefused;
      }
    }

    final presentation = degradation == DVWindowDegradation.none
        ? DVWindowPresentation.window
        : _presentationFor(options.kind);

    final window = DVWindow(
      route: route,
      kind: options.kind,
      presentation: presentation,
      degradation: degradation,
      nativeId: nativeId,
    );
    _windows.add(window);
    _all.value = List<DVWindow>.unmodifiable(_windows);

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
    await shared.set(_workspaceKey(name), DVJsonList(layout));
    await shared.flush(_workspaceKey(name));
  }

  /// Restores what [persistWorkspace] saved, or an empty list when nothing is
  /// stored — a first launch is not a failure.
  Future<List<DVTabWorkspaceController>> restoreWorkspace(String name) async {
    final stored = await shared.get(_workspaceKey(name));
    if (stored is! DVJsonList) return <DVTabWorkspaceController>[];

    final restored = <DVTabWorkspaceController>[];
    for (final entry in stored.value) {
      if (entry is! DVJsonMap) continue;
      final tabs = entry.value['tabs'];
      if (tabs is! DVJsonList) continue;
      final controller = DVTabWorkspaceController(
        tabs: <DVTab>[
          for (final path in tabs.value)
            if (path is DVJsonString) DVTab(DVRouteTarget(path.value)),
        ],
      );
      final active = entry.value['active'];
      if (active is DVJsonNumber) controller.activate(active.value.toInt());
      restored.add(controller);
    }
    return restored;
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
    await shared.set(dvWindowStateKey(key), DVJsonString(state.encode()));
    await shared.flush(dvWindowStateKey(key));
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
    final stored = await shared.get(dvWindowStateKey(key));
    if (stored is! DVJsonString) return;

    final state = DVWindowState.decode(stored.value);
    if (state == null) return;

    await DVNativeBridge.invoke<bool>('window.setSize', <String, Object?>{
      'width': state.width,
      'height': state.height,
    });
  }
}
