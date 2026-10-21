/// Real OS windows for Dartvel desktop applications.
///
/// Depending on this package registers the `window.open` binding, which is
/// what flips `DVWindowingCapability.multiWindow` true — see the README for
/// why this is a separate package from `dartvel_flutter`.
///
/// In a browser there are no OS windows to open: [DVWindowHost] shows its
/// home and registers nothing, and `DV.Platform.window.open` navigates to the
/// route as it does in any app without this package. So an application that
/// opens a projector window on a desktop builds for the web unchanged.
library dartvel_windowing;

export 'src/windowing_web.dart' if (dart.library.ffi) 'src/windowing_native.dart';
