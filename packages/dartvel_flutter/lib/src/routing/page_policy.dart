/// The check a page's declared policy runs before its route activates.
///
/// `@DVPage(policy: ...)` was accepted by the annotation and read by nothing.
/// A developer who wrote it got a page anybody could open, and nothing said
/// so -- which is the worst shape an authorization bug takes: it fails open
/// at the one place the API invited them to trust it.
///
/// The generated router calls this. It lives here rather than being inlined
/// into generated source so the auth surface it consults can change without
/// every generated router in every application pinning the old shape.
library dartvel_flutter.routing.page_policy;

/// Where a refused request goes.
///
/// A default rather than a constant, and the same one the role guard already
/// uses, so an application that has styled that page does not acquire a
/// second one it has never seen.
String dvUnauthorizedRoute = '/unauthorized';

/// Answers whether this caller may open a route, for the generated router.
class DVPagePolicy {
  const DVPagePolicy._();

  /// What decides. Set by the generated bootstrap from the application's own
  /// auth, and left null in tests and in applications that have none.
  ///
  /// Null is not "allow". A page carrying a policy in an application with no
  /// way to answer it is refused, because the alternative is a page that
  /// declares a guard and opens for everybody -- the exact bug this exists
  /// to close, reintroduced as a default.
  static Future<bool> Function(String policy, String location)? decide;

  /// The route to redirect to, or null to let the page render.
  static Future<String?> check(
    Object? context,
    Object? state,
    String policy,
  ) async {
    final Future<bool> Function(String, String)? answer = decide;
    if (answer == null) return dvUnauthorizedRoute;
    final String location = _locationOf(state);
    return await answer(policy, location) ? null : dvUnauthorizedRoute;
  }

  /// The path a router state names, without depending on the router's type.
  ///
  /// Taken dynamically because this file is compiled into applications whose
  /// router is generated: importing go_router here would make the routing
  /// engine an implementation detail of one more file, and the engine is
  /// meant to stay behind the generated surface.
  static String _locationOf(Object? state) {
    if (state == null) return '';
    try {
      // ignore: avoid_dynamic_calls
      final Object? location = (state as dynamic).matchedLocation;
      return location is String ? location : '';
    } on NoSuchMethodError {
      return '';
    }
  }
}
