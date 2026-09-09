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
/// The specification puts the annotation on "any widget, whether
/// Flutter-native, `DVClassWidget`, or `DVFunctionalWidget`", so the class
/// shape is matched as well as the function shape -- and it is matched
/// first, which is the whole of the fix. The function branch's return type
/// is deliberately loose, because a widget-returning function may be written
/// with any of several types, and loose enough to swallow
/// `class _StepCounter extends` and take `StatelessWidget` for the declared
/// name. What came of that was a message telling the developer to rename a
/// class in the Flutter SDK, about a widget nothing had read.
///
/// Read the pieces out with [dvHomeWidgetAnnotationArgs],
/// [dvHomeWidgetDeclaredName] and [dvHomeWidgetIsClass] rather than by group
/// number: two scanners share this, and a group index counted by hand in
/// each is a scan that silently reads the wrong capture when the pattern
/// grows another one.
final RegExp dvHomeWidgetDeclaration = RegExp(
  r'@DVHomeWidget\(([^)]*)\)\s*(?:@[A-Za-z_][\w.]*\([^)]*\)\s*)*'
  r'(?:class\s+(?<widgetClass>[A-Za-z_][A-Za-z0-9_]*)\b'
  r'|(?:Widget|[A-Za-z_][\w<>, ?]*)\s+(?<widgetFunction>[A-Za-z_][A-Za-z0-9_]*)\s*\()',
);

/// Whatever the `@DVHomeWidget` in [match] was given, as written.
String dvHomeWidgetAnnotationArgs(RegExpMatch match) => match.group(1) ?? '';

/// The name declared under the `@DVHomeWidget` in [match].
///
/// The function's name or the class's, whichever shape it was written in.
String dvHomeWidgetDeclaredName(RegExpMatch match) =>
    match.namedGroup('widgetClass') ?? match.namedGroup('widgetFunction')!;

/// Whether [match] declared a widget class rather than a widget function.
///
/// The two are generated differently and cannot be told apart afterwards: a
/// function is lowered into a widget class the generator writes and owns, and
/// a class is the developer's own, referenced where it already lives.
bool dvHomeWidgetIsClass(RegExpMatch match) =>
    match.namedGroup('widgetClass') != null;

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

/// The host a home widget's launch link carries.
///
/// It says what kind of link this is, which is the only thing separating a
/// widget's tap from an ordinary `dartvel://` deep link the application also
/// handles. Without a host of its own the route would start at the
/// authority, and `dartvel://widgets/order-status` parses with `widgets` as
/// the host and `order-status` as the whole path -- so an application that
/// handles both kinds of link could not tell them apart at all.
const String dvHomeWidgetLaunchHost = 'widget';

/// The URL scheme a home widget's tap opens the application with.
///
/// One value, because three things have to agree on it and only one of them
/// is Dart: the generated Java that fires the intent, the generated Swift
/// that hands the URL to WidgetKit, and the desktop launch path that decides
/// whether an argument is a link at all.
///
/// It is the framework's scheme rather than the application's, and that is
/// worth stating rather than leaving as an oversight. On Android the intent
/// names the Activity outright, so nothing resolves the scheme and a shared
/// one costs nothing. On Apple the URL is handed to the containing
/// application by WidgetKit rather than through LaunchServices, so it costs
/// nothing there either. Where it would cost something is an application
/// that also wants `dartvel://` links from outside itself, and giving it a
/// scheme of its own is a change that cannot be checked without a device.
const String dvHomeWidgetLaunchScheme = 'dartvel';

/// The link a home widget's tap opens the application with.
///
/// [scheme] is the application's own URL scheme and [route] the route the
/// widget was generated for. Both native halves write this: Android's
/// provider puts it in the PendingIntent, and WidgetKit's view hands it to
/// `widgetURL`. One rule, because the runtime reads it back with
/// [dvHomeWidgetRouteForLink] and two spellings is a tap that opens the
/// not-found page on one platform and the right page on the other.
String dvHomeWidgetLaunchUrl(String scheme, String route) =>
    '$scheme://$dvHomeWidgetLaunchHost$route';

/// The route [link] asks for when it is a home widget's tap, else null.
///
/// The inverse of [dvHomeWidgetLaunchUrl], and the half that did not exist.
/// Both platforms launched the application at a URL naming the widget's
/// route, and the general rule for a `dartvel://` link folds the host back
/// into the path -- so `dartvel://widget/widgets/order-status` came out as
/// `/widget/widgets/order-status`, which no router has. A widget on somebody's
/// home screen opened the not-found page, and nothing at either end had
/// anything to report.
///
/// Null for everything that is not this exact shape. Claiming a link that
/// merely carries the host would send a half-written URL to `/widgets/`,
/// which matches no widget and reads as one that was removed.
String? dvHomeWidgetRouteForLink(String link) {
  final Uri? uri = Uri.tryParse(link.trim());
  if (uri == null || !uri.hasScheme) return null;
  if (uri.host != dvHomeWidgetLaunchHost) return null;
  final List<String> segments = uri.pathSegments;
  if (segments.length != 2 || segments[0] != 'widgets') return null;
  final String id = segments[1];
  if (id.isEmpty) return null;
  // Through the same function the build wrote the route with, rather than
  // rebuilt from the pieces here. That is what keeps the two ends from
  // drifting when the route shape changes.
  return dvHomeWidgetRoute(id);
}

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

/// The Objective-C class name of the Swift shim that redraws a home widget
/// on Apple platforms.
///
/// WidgetCenter is Swift-only and has no Objective-C class to message, so
/// nothing in Dart can reach it: `objc_getClass("WidgetCenter")` answers nil
/// on a device where WidgetKit is working perfectly. What can be reached is
/// a class compiled into the application that calls it, which is what
/// `dartvel build` writes.
///
/// In core because both halves need it and they are in different packages:
/// the build writes the Swift that declares this name, and the Flutter
/// runtime looks it up by string. Two spellings is a lookup that answers nil
/// for ever -- and nil is also the honest answer for an application built
/// with plain `flutter build`, so the two are indistinguishable and neither
/// reports anything.
const String dvHomeWidgetAppleReloadClass = 'DartvelWidgetCenter';

/// The selector the shim answers to.
///
/// Named beside the class for the same reason. A selector that does not
/// exist is not a nil lookup: it is an unrecognised-selector exception,
/// which is loud, and which arrives on a device rather than in a build.
const String dvHomeWidgetAppleReloadSelector = 'reloadAll';

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
