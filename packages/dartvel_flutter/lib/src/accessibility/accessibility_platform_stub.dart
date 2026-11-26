/// No browser and no file system: settings live for this run only, and the
/// operating system's wishes come through Flutter's MediaQuery alone.
library;

import 'accessibility_store.dart';

DVAccessibilityStore dvPlatformAccessibilityStore(String app) => DVMemoryAccessibilityStore();

/// Whether the browser says the visitor wants more contrast.
bool dvSystemPrefersContrast() => false;

/// Whether the browser says the visitor wants less motion.
bool dvSystemPrefersReducedMotion() => false;

/// Calls [changed] whenever either of the two above changes.
void dvWatchSystemPreferences(void Function() changed) {}
