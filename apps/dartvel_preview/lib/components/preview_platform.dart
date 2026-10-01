/// What this build of Dartvel Preview can do on the platform it runs on.
///
/// Chosen at compile time: a browser build has a frame and no process, a
/// native build has a process and no frame.
library;

export 'preview_platform_stub.dart'
    if (dart.library.io) 'preview_platform_io.dart'
    if (dart.library.js_interop) 'preview_platform_web.dart';
