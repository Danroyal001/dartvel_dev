import 'dart:io';

import 'display_availability.dart';

/// Whether this process can open a window: on Linux, a display server named
/// by the environment; on a desktop OS, always.
bool dvDisplayAvailable() => dvDisplayAvailableIn(Platform.environment, os: Platform.operatingSystem);
