/// The half of dartvel_shelf that a frontend may import.
///
/// `dartvel_core` depends on this package for its request and response types,
/// so every Dartvel application pulls it whether or not it ever serves. Those
/// types are plain Dart and belong on both sides of the wire; the server is
/// native, and belongs only on one.
///
/// Importing this entrypoint cannot reach `dart:ffi` or the server, which is
/// checked by a test that walks the import graph rather than by convention.
/// An application that serves imports `package:dartvel_shelf/backend.dart`.
library dartvel_shelf.core;

export 'src/router.dart' show Router;
export 'src/wintercg.dart' show Request, Response, Headers, Body, URLPattern;
