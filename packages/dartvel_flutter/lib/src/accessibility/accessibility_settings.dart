// ignore_for_file: unused_element, unused_element_parameter
// The input for DVAccessibilitySettings: a model kept on the visitor's
// device, generated into accessibility_settings.g.dart by
// tool/generate_framework_models.dart with the same emitter an application's
// @DVModel(storage: DVModelStorage.device) goes through. Edit this, then run
// the tool; a test fails when the generated file is out of date.
import 'package:dartvel_core/dartvel.dart';

/// What a visitor chose in the accessibility panel. The operating system's
/// own settings (reduce motion, more contrast, its text size) always count on
/// top of these. Kept as `{textScale, highContrast, reducedMotion}`, which
/// the SSR-first head reads before the first paint.
@DVModel(storage: DVModelStorage.device, storageKey: 'dartvel.accessibility')
class const _DVAccessibilitySettings({
  final double textScale = 1.0,
  final bool highContrast = false,
  final bool reducedMotion = false,
});
