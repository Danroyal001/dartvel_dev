// One route out of a generated router.
//
// Written because the same mistake happened three times in one day: an
// assertion about one route made against the whole generated file.
//
// It goes wrong in both directions. Asserting a route *has* something
// against the whole file passes when a different route has it, or when the
// helper it names is simply declared there -- `_dvGuarded` is emitted into
// every generated router whether anything calls it or not, so
// `isNot(contains('_dvGuarded'))` asked whether the helper exists rather
// than whether this route uses it. And a fixed window of a few hundred
// characters after the path spills into the next route, so a correct guard
// on the next one reads as a missing guard on this one.
//
// Both are the same fix: bound the text to the route it belongs to.
library;

/// The generated source for the route at [path], up to the next route.
///
/// Throws rather than returning empty when the path is not registered, since
/// an assertion against an empty string passes for every `isNot` in it --
/// which is how a test can go green against a router that does not contain
/// the route at all.
String dvRouteSource(String routerSource, String path) {
  final int at = routerSource.indexOf("'$path'");
  if (at < 0) {
    throw ArgumentError.value(
      path,
      'path',
      'is not registered in this generated router. Registered: '
          '${dvRegisteredPaths(routerSource).join(', ')}',
    );
  }
  final int next = routerSource.indexOf('router.', at);
  return routerSource.substring(at, next == -1 ? routerSource.length : next);
}

/// Every path the generated router registers, in the order it registers them.
///
/// Only used to say what was there when a lookup fails, which is the moment
/// somebody needs it.
List<String> dvRegisteredPaths(String routerSource) => RegExp(
      r"cfg\.apiBasePath \+ '([^']*)'",
    ).allMatches(routerSource).map((RegExpMatch m) => m.group(1)!).toList();
