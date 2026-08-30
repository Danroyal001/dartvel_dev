/// Whether an application asked for the native server to be built into it.
///
/// `dartvel_core` depends on this package for its request and response types,
/// so every Dartvel application pulls it whether or not it ever serves
/// anything. Building the Axum server regardless put a full HTTP server --
/// with TLS and a static file handler -- inside client binaries that never
/// listen: 7.2 MB of `dartvel_shelf.dll`, 6.5 MB of `libdartvel_shelf.so`, or
/// a `dartvel_shelf.framework`.
///
/// It is the same rule the project already applies to rendering backends:
/// never link one by default, and no application gets one it did not ask for.
library dartvel_shelf.build.embed_decision;

/// The pubspec key an application sets to embed the server.
///
/// ```yaml
/// hooks:
///   user_defines:
///     dartvel_shelf:
///       embed_server: true
/// ```
const String dvEmbedServerDefine = 'embed_server';

/// Reads the opt-in from a user-define value.
///
/// Absent means no. The value is read rather than its key merely being
/// present, so `embed_server: false` turns the feature off instead of
/// requiring the line to be deleted.
///
/// A string is accepted because a define supplied on the command line arrives
/// as one, where the same setting from a pubspec arrives as a bool.
bool dvEmbedServerRequested(Object? define) {
  if (define is bool) return define;
  if (define is String) {
    final String value = define.trim().toLowerCase();
    return value == 'true' || value == '1' || value == 'yes';
  }
  // Anything else -- a number, a map, a typo like `embed_server: yes please` --
  // is not a request. Guessing here would link a server into an application on
  // the strength of a malformed line.
  return false;
}
