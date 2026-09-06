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
    this.title,
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

  /// What a person sees it called: the `title` the annotation was given, and
  /// null when it was given none.
  ///
  /// It is a shell property a page has, and it is also the only one that
  /// leaves the application: a launcher's widget picker and WidgetKit's
  /// gallery both need a name, and until this existed they were shown [id],
  /// which is a route segment.
  final String? title;

  /// The name to show wherever a platform asks for one.
  ///
  /// The identifier is the fallback rather than an empty string, because a
  /// widget with no name in a picker cannot be picked -- and an empty label
  /// is not something a build can see.
  String get label => (title == null || title!.isEmpty) ? id : title!;

  @override
  String toString() => 'DVHomeWidgetSpec($id at $route)';
}

/// The declaration a `@DVHomeWidget` annotation sits above.
///
/// One pattern, in core, because two scanners read it: the generator that
/// writes the page and the route, and the build check that decides whether
/// the target being built has anywhere to put one. They held a copy each,
/// and both copies matched the literal `@DVHomeWidget()` -- empty parentheses
/// included. Giving a widget the shell properties the specification promises
/// therefore deleted it: no entry in the generated list, no route, no
/// provider, no extension, and no message anywhere, with the annotation still
/// in the file saying otherwise.
///
/// Group 1 is whatever the annotation was given, group 2 the declared name.
final RegExp dvHomeWidgetDeclaration = RegExp(
  r'@DVHomeWidget\(([^)]*)\)\s*(?:@[A-Za-z_][\w.]*\([^)]*\)\s*)*'
  r'(?:Widget|[A-Za-z_][\w<>, ?]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*[({]',
);

/// Whether [source] is worth scanning for a home widget at all.
///
/// The cheap check the scanners do before the regular expression. It was
/// `contains('@DVHomeWidget()')`, which is the same bug as the pattern: a
/// file whose only home widget carried arguments was skipped before anything
/// looked at it.
bool dvSourceDeclaresHomeWidget(String source) =>
    source.contains('@DVHomeWidget(');

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

/// The user-defaults key an iOS launch URL is left under.
///
/// In core rather than beside either half, because both halves need it and
/// they are in different packages: the build writes the capture into
/// `AppDelegate.swift`, and the Flutter runtime reads it back through the
/// Objective-C runtime. Two spellings of it is a launch that is captured and
/// never read, with nothing to see at either end.
const String dvIosLaunchUrlKey = 'dartvel.launchURL';
