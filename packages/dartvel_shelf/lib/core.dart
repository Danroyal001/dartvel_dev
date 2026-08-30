/// A compatibility re-export of the wire types.
///
/// The types themselves now live in `dartvel_core`, which is on both sides of
/// the wire. That is the direction the dependency should always have run: a
/// frontend reached into this package for three type names and acquired a
/// server package along with them.
///
/// Kept so anything importing this entrypoint keeps working. New code should
/// import `package:dartvel_core/dartvel.dart`. An application that serves
/// imports `package:dartvel_shelf/backend.dart`.
library dartvel_shelf.core;

// The wire types moved to dartvel_core, which is on both sides of the wire.
// Re-exported here so anything importing this entrypoint keeps working.
export 'package:dartvel_core/http.dart';
