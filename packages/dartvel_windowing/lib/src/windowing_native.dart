/// Real OS windows for Dartvel desktop applications.
///
/// Depending on this package registers the `window.open` binding, which is
/// what flips `DVWindowingCapability.multiWindow` true — see the README for
/// why this is a separate package from `dartvel_flutter`.
///
/// The library is deliberately one library made of parts rather than several:
/// the windowing contract says anything beyond `DV.Window` and `DVWindow` is
/// private, and Dart privacy is per library, so the binding registrar can only
/// be private if everything that uses it is part of the same one.
library dartvel_windowing.native;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';
// ignore: invalid_use_of_internal_member
import 'package:flutter/src/foundation/_features.dart';
// ignore: invalid_use_of_internal_member
import 'package:flutter/src/widgets/_window.dart';
// ignore: invalid_use_of_internal_member, implementation_imports
import 'package:flutter/src/widgets/_window_linux.dart' show WindowControllerLinux;
import 'package:flutter/widgets.dart';

part 'linux_displays_ffi.dart';
part 'linux_window_ffi.dart';
part 'macos_displays_ffi.dart';
part 'windows_displays_ffi.dart';
part 'flutter_window_surface.dart';
part 'window_bindings.dart';
part 'window_host.dart';
part 'window_surfaces.dart';
