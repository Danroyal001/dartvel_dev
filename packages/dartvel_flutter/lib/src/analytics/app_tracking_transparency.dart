/// App Tracking Transparency: the system prompt iOS and tvOS require before
/// an application tracks somebody across other companies' apps and sites.
///
/// A consent category declared `tracking: true` is granted there only when
/// this prompt allows it. The banner saying yes does not overrule the
/// system saying no, and a prompt that could not be shown -- no binding, no
/// usage description in Info.plist, a system too old to have the framework --
/// grants nothing.
library dartvel_flutter.analytics.app_tracking_transparency;

import 'package:flutter/foundation.dart';

import '../../dartvel_flutter.dart' show DVNativeBridge;

/// What the system prompt answered.
enum DVTrackingAuthorization {
  /// Nobody has been asked yet.
  notDetermined,

  /// Tracking is not allowed on this device, by a profile or parental
  /// control; the person could not have been asked.
  restricted,

  /// The person said no.
  denied,

  /// The person said yes.
  authorized,

  /// There was no prompt to show.
  unavailable,
}

/// The App Tracking Transparency prompt, through the platform binding.
abstract final class DVAppTrackingTransparency {
  /// The binding that shows the prompt and answers with
  /// `ATTrackingManagerAuthorizationStatus`, or -1 when it cannot be shown.
  static const String requestBinding = 'tracking.requestAuthorization';

  /// Whether this platform asks tracking categories through the prompt.
  ///
  /// iOS, which is also what Flutter reports on tvOS. Replaceable for tests.
  static bool Function() applies = _onApplePlatform;

  static bool _onApplePlatform() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Shows the prompt, or answers what it answered before.
  ///
  /// [DVTrackingAuthorization.unavailable] when there is no binding or the
  /// binding could not show it, and never an exception: a consent flow that
  /// threw here would leave the person's other answers unsaved.
  static Future<DVTrackingAuthorization> request() async {
    if (!DVNativeBridge.isRegistered(requestBinding)) {
      return DVTrackingAuthorization.unavailable;
    }
    try {
      final Object? status =
          await DVNativeBridge.invoke<Object?>(requestBinding);
      return switch (status) {
        0 => DVTrackingAuthorization.notDetermined,
        1 => DVTrackingAuthorization.restricted,
        2 => DVTrackingAuthorization.denied,
        3 => DVTrackingAuthorization.authorized,
        _ => DVTrackingAuthorization.unavailable,
      };
    } on Object catch (error) {
      debugPrint('[dartvel] App Tracking Transparency could not be asked: '
          '$error');
      return DVTrackingAuthorization.unavailable;
    }
  }
}
