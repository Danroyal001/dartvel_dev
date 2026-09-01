/// Real OS windows for Dartvel desktop applications.
///
/// Depending on this package registers the `window.open` binding, which is
/// what flips `DVWindowingCapability.multiWindow` true — see the README for
/// why this is a separate package from `dartvel_flutter`.
library dartvel_windowing;

export 'src/flutter_window_surface.dart';
export 'src/window_host.dart';
export 'src/window_surfaces.dart';
export 'src/windowing.dart';
