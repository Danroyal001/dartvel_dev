/// The one check every animation Dartvel runs goes through.
///
/// Flutter reports two settings. `disableAnimations` is Android's "Remove
/// animations" (and, on the web, `prefers-reduced-motion`); it is the one
/// Flutter's own AnimationController obeys. `reduceMotion` (Flutter 3.50) is
/// iOS "Reduce Motion", and Flutter leaves it to each widget. Reading only
/// the first, as every Dartvel site used to, left an iPhone with Reduce
/// Motion on watching every page slide in. Either setting, or the
/// application's own `DV.Accessibility.useReducedMotion(true)`, makes Dartvel
/// jump to the end state.
///
/// Not exported: an application reads `context.screen.reducedMotion` or
/// `DV.Accessibility.reducedMotion`.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The application's override, set through `DV.Accessibility`. Null follows
/// the platform.
bool? dvReducedMotionOverride;

/// Whether the platform asks for less movement, with no widget to ask:
/// either accessibility feature, unless the application overrode it.
bool dvPlatformReducedMotion() {
  final bool? override = dvReducedMotionOverride;
  if (override != null) return override;
  final ui.AccessibilityFeatures features =
      _dispatcher().accessibilityFeatures;
  return features.disableAnimations || features.reduceMotion;
}

/// The binding's dispatcher, which is what a test or an embedder overrides;
/// the engine's own before a binding exists.
ui.PlatformDispatcher _dispatcher() {
  try {
    return WidgetsBinding.instance.platformDispatcher;
  } on FlutterError {
    return ui.PlatformDispatcher.instance;
  }
}

/// Whether motion should be skipped for what is built under [context].
///
/// [listen] false reads without depending on the MediaQuery, for a caller
/// outside a build (a route deciding its duration as it is pushed).
bool dvReducedMotion(BuildContext context, {bool listen = true}) {
  final MediaQueryData? data = listen
      ? null
      : context.getInheritedWidgetOfExactType<MediaQuery>()?.data;
  final bool disable = listen
      ? (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
      : (data?.disableAnimations ?? false);
  final bool reduce = listen
      ? (MediaQuery.maybeReduceMotionOf(context) ?? false)
      : (data?.reduceMotion ?? false);
  return disable || reduce || dvPlatformReducedMotion();
}

/// [duration], or zero when motion should be skipped under [context].
Duration dvMotionDuration(BuildContext context, Duration duration) =>
    dvReducedMotion(context) ? Duration.zero : duration;
