/// Opening a checkout page outside the application, behind a conditional
/// import: a browser navigates, a desktop asks the operating system.
library dartvel_flutter.purchases.open_url;

export 'open_url_io.dart' if (dart.library.js_interop) 'open_url_web.dart';
