/// `DV` for the server side: backend functions, jobs and the server itself.
///
/// Pure Dart, so a `dartvel build web-server` binary can import it. The
/// Flutter layer declares the application's `DV`, with pages and navigation
/// on it; both are spelled the same at every call site, and a file that
/// imports the generated client gets the application's.
library dartvel_core.dv_library;

export 'src/dv.dart';
