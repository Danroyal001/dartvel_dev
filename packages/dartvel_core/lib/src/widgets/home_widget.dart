/// A home-screen widget the application declares.
///
/// The specification puts `@DVHomeWidget()` on any widget and says home
/// widgets act like a page: they support the same shell properties, they can
/// launch and navigate to pages within the application, and Dartvel
/// generates a page that centres the widget's content.
///
/// This is what the build knows about each one. The native half -- a Glance
/// widget on Android, a WidgetKit extension on iOS -- is packaging around
/// exactly this: an identifier, a name and the route that shows it.
library;

class DVHomeWidgetSpec {
  const DVHomeWidgetSpec({
    required this.id,
    required this.name,
    required this.route,
  });

  /// The identifier the platform knows it by: the widget's name in kebab
  /// case, with the word `Widget` taken off. Stable, because a home widget
  /// somebody has placed on their screen is found again by this.
  final String id;

  /// The generated widget class the page builds.
  final String name;

  /// Where the application shows it: `/widgets/<id>`. A widget that could
  /// launch the application and not say where to would be a shortcut to the
  /// home screen.
  final String route;

  @override
  String toString() => 'DVHomeWidgetSpec($id at $route)';
}

/// The route a home widget with [id] is shown at.
///
/// One rule, used by the generator that writes the route and by anything
/// resolving a launch back to it: two spellings of this is how a widget's
/// tap opens the not-found page.
String dvHomeWidgetRoute(String id) => '/widgets/$id';

/// The identifier for a generated widget class.
///
/// `StepCounterWidget` is `step-counter`. The trailing `Widget` goes because
/// every one of them has it and it says nothing.
String dvHomeWidgetId(String className) {
  final String bare = className.endsWith('Widget') && className.length > 6
      ? className.substring(0, className.length - 6)
      : className;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < bare.length; i++) {
    final String character = bare[i];
    final String lower = character.toLowerCase();
    if (character != lower && out.isNotEmpty) out.write('-');
    out.write(lower);
  }
  return out.isEmpty ? 'widget' : out.toString();
}
