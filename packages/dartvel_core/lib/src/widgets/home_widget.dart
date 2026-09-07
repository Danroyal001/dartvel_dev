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

/// [id] with everything a platform identifier may not carry taken out.
///
/// Identifiers are kebab case, and a hyphen is fine in a defaults key and
/// not fine in a Swift type or an Android resource name. One spelling of the
/// substitution, so the name the extension is built with and the name the
/// application writes under cannot come out differently.
String dvHomeWidgetPlatformName(String id) =>
    id.replaceAll(RegExp('[^A-Za-z0-9]'), '_');

/// The kind string WidgetKit addresses a widget by.
///
/// Two widgets sharing a kind is a reload of the wrong one and a timeline
/// written into the wrong one, with no error at either end.
String dvHomeWidgetKind(String id) =>
    'dartvel.widget.${dvHomeWidgetPlatformName(id)}';

/// Where a home widget's data is left for the surface that draws it.
///
/// This is the whole of what "shares state with the parent app" can mean
/// once the boundary is honest about itself. A home widget is composed in
/// the launcher's process on Android and by the system on iOS and macOS, and
/// neither can host a Flutter engine, so the widget tree and its state are
/// shared with the application at `/widgets/<id>` -- the application's own
/// tree, its own signals, its own globals -- and what crosses to the home
/// screen is a value under a key.
///
/// In core because three halves need it and they are in three languages:
/// the Dart runtime writes it, the generated Swift reads it out of the App
/// Group defaults, and the generated Java reads it out of the shared store.
/// A key with two spellings is a correctly built, correctly signed widget
/// showing its placeholder for ever, with nothing to see at any end.
String dvHomeWidgetDataKey(String id) =>
    'dartvel.widget.text.${dvHomeWidgetPlatformName(id)}';

/// The App Group the application and its widget extension share on Apple
/// platforms, derived from the application's own bundle id.
///
/// Per application for the reason an Android provider authority is: a
/// constant here means the second Dartvel application installed reads the
/// first one's container, or is refused the entitlement and shows a
/// placeholder nobody can explain.
String dvHomeWidgetAppGroup(String bundleId) =>
    'group.$bundleId.dartvelwidgets';

/// The class the Android half of a publish goes through, in JNI's
/// slash-separated form.
///
/// A fixed package rather than the application's own, for the reason
/// `DartvelContext` has one: Dart finds this class by name, and the
/// application's package is an applicationId the framework cannot know when
/// the lookup is compiled. `dartvel build android` writes it, and only for a
/// project that declares a widget -- so the lookup failing is the honest
/// answer "this application has no home widgets", not an error.
const String dvHomeWidgetAndroidClass = 'dev/dartvel/jni/DartvelWidgets';

/// The Android shared store a home widget's data is written into and read
/// back out of.
///
/// The provider is a BroadcastReceiver in the application's own process --
/// only the RemoteViews it returns are handed to the launcher -- so ordinary
/// SharedPreferences reach both ends, and no content provider or App Group
/// equivalent is needed. Two spellings of the name is a widget reading an
/// empty store.
const String dvHomeWidgetAndroidStore = 'dartvel.widgets';

/// The user-defaults key an iOS launch URL is left under.
///
/// In core rather than beside either half, because both halves need it and
/// they are in different packages: the build writes the capture into
/// `AppDelegate.swift`, and the Flutter runtime reads it back through the
/// Objective-C runtime. Two spellings of it is a launch that is captured and
/// never read, with nothing to see at either end.
const String dvIosLaunchUrlKey = 'dartvel.launchURL';

/// The device-admin receiver class `dartvel build android` writes.
///
/// In core because both halves need it and they are in different packages:
/// the build writes the receiver and the manifest entry that names it, and
/// the Flutter runtime addresses the same component when it allowlists the
/// application for lock task. Two spellings of it is a device owner set
/// against a component that does not exist, which Android reports as an
/// unknown admin and which took four layers of this to find once already.
const String dvAndroidDeviceAdminClass = 'DartvelDeviceAdminReceiver';
