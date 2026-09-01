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
library dartvel_windowing;

import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';
// ignore: invalid_use_of_internal_member
import 'package:flutter/src/foundation/_features.dart';
// ignore: invalid_use_of_internal_member
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';

part 'src/linux_displays_ffi.dart';
part 'src/flutter_window_surface.dart';
part 'src/window_bindings.dart';
part 'src/window_host.dart';
part 'src/window_surfaces.dart';
