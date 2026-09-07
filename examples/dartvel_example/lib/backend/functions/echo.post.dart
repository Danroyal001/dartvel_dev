import 'package:dartvel_core/dartvel.dart';

/// A body limit, so the capped read is compiled rather than only asserted on
/// as a string.
///
/// The check cannot be a middleware -- the chain runs around the handler and
/// the body is in memory by then -- so the generator emits it into the
/// request prelude, and this is the only place a compiler sees that shape.
@DVUseMiddleware(<DVMiddlewareKey>[DVMiddlewares.bodyLimit])
Map<String, Object?> echo(String msg) => <String, Object?>{'echo': msg};
