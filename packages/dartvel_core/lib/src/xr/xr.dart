/// XR: presenting a scene in space.
///
/// The platform-independent half: poses and conventions, capability, the
/// device adapter contract with a headless device, and the session that
/// couples a presentation in space to lifecycle, permissions and consent.
/// The window kinds that ask for it live on `DV.Window` in dartvel_flutter.
library dartvel.xr;

export 'spatial_capability.dart';
export 'spatial_comfort.dart';
export 'spatial_consent.dart';
export 'spatial_input.dart';
export 'spatial_pose.dart';
export 'spatial_session.dart';
export 'xr_device.dart';
