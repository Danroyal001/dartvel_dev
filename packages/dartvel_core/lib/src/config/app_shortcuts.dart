/// `dartvel.appShortcuts`: the actions a person reaches by long-pressing the
/// application's icon (Android, iOS), right-clicking it (Linux, PWA on the
/// desktop) or from an installed web app's shortcuts menu.
///
/// One declaration, and the build writes it where each platform looks: the
/// web manifest's `shortcuts`, Android's `shortcuts.xml`, iOS's
/// `UIApplicationShortcutItems`, a Linux desktop entry's actions. Nobody
/// edits a native folder for it.
///
/// ```yaml
/// dartvel:
///   appShortcuts:
///     - id: new-order
///       title: New order
///       route: /orders/new
///       subtitle: Start an order from scratch
/// ```
///
/// The same list in a Dart config class is `List<DVAppShortcut>`, and
/// [DVAppShortcut.toPubspec] writes exactly the map above: same keys, same
/// defaults, same validation, so the two spellings are one configuration.
library;

/// One action on the application's icon.
class DVAppShortcut {
  const DVAppShortcut({
    required this.id,
    required this.title,
    required this.route,
    this.subtitle,
    this.icon,
  });

  /// Stable identifier. Platforms keep a shortcut a person pinned by its id,
  /// so renaming the title keeps it and changing the id replaces it.
  final String id;

  /// What the menu shows. Short: Android truncates a label past about ten
  /// characters on some launchers and uses [subtitle] where there is room.
  final String title;

  /// The page it opens, as a path of this application (`/orders/new`).
  final String route;

  /// A longer line where the platform shows one: iOS's subtitle, Android's
  /// long label, the web manifest's description.
  final String? subtitle;

  /// An image under the web build for the PWA shortcut (`icons/new.png`).
  /// Platforms that draw their own icon set leave it out.
  final String? icon;

  /// How many shortcuts a launcher shows. Android and iOS show four; the
  /// rest are kept by the platform but never displayed, which reads as a
  /// declaration that silently half-worked, so more than this is a problem.
  static const int shownByLaunchers = 4;

  /// The `dartvel:` value, keys in a fixed order, optional keys left out
  /// when unset.
  Map<String, Object?> toPubspec() => <String, Object?>{
        'id': id,
        'title': title,
        'route': route,
        if (subtitle != null) 'subtitle': subtitle,
        if (icon != null) 'icon': icon,
      };

  /// The link a platform launches the application with to open [route]:
  /// `dartvel:///orders/new`. An empty host, so both the Android launch
  /// parser (which reads the path) and the shared launcher (which folds a
  /// host into the path) arrive at the same route.
  String get launchLink => 'dartvel://$route';

  @override
  bool operator ==(Object other) =>
      other is DVAppShortcut &&
      other.id == id &&
      other.title == title &&
      other.route == route &&
      other.subtitle == subtitle &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(id, title, route, subtitle, icon);

  @override
  String toString() => 'DVAppShortcut($id, $route)';
}

/// What reading `dartvel.appShortcuts` found.
class DVAppShortcutsConfig {
  const DVAppShortcutsConfig(this.shortcuts, {this.problems = const <String>[]});

  final List<DVAppShortcut> shortcuts;

  /// Why an entry was left out, or why the list will not display as written.
  /// Reported rather than thrown, so one bad entry costs that entry.
  final List<String> problems;

  /// The `dartvel.appShortcuts` value for [shortcuts].
  static List<Map<String, Object?>> toPubspec(List<DVAppShortcut> shortcuts) =>
      <Map<String, Object?>>[for (final DVAppShortcut shortcut in shortcuts) shortcut.toPubspec()];

  static final RegExp _id = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  /// Reads the `dartvel.appShortcuts` value, as YAML or as the map a Dart
  /// config class wrote. Validation is here and only here, so both spellings
  /// are refused for the same reasons in the same words.
  static DVAppShortcutsConfig parse(Object? value) {
    if (value == null) return const DVAppShortcutsConfig(<DVAppShortcut>[]);
    if (value is! List) {
      return const DVAppShortcutsConfig(<DVAppShortcut>[],
          problems: <String>['dartvel.appShortcuts must be a list of shortcuts.']);
    }
    final List<DVAppShortcut> shortcuts = <DVAppShortcut>[];
    final List<String> problems = <String>[];
    final Set<String> ids = <String>{};
    for (int index = 0; index < value.length; index++) {
      final Object? entry = value[index];
      final String where = 'dartvel.appShortcuts[$index]';
      if (entry is! Map) {
        problems.add('$where is not a map.');
        continue;
      }
      String? text(String key) {
        final Object? raw = entry[key];
        if (raw == null) return null;
        final String trimmed = '$raw'.trim();
        return trimmed.isEmpty ? null : trimmed;
      }

      for (final Object? key in entry.keys) {
        if (!const <String>{'id', 'title', 'route', 'subtitle', 'icon'}.contains(key)) {
          problems.add('$where has an unknown key "$key"; the keys are id, title, route, subtitle and icon.');
        }
      }
      final String? id = text('id');
      final String? title = text('title');
      final String? route = text('route');
      if (id == null || !_id.hasMatch(id)) {
        problems.add('$where needs an id of lowercase letters, digits, - and _, such as new-order.');
        continue;
      }
      if (!ids.add(id)) {
        problems.add('$where: the id "$id" is used twice; a platform keeps shortcuts by id.');
        continue;
      }
      if (title == null) {
        problems.add('$where ($id) needs a title.');
        continue;
      }
      if (route == null || !route.startsWith('/') || route.startsWith('//')) {
        problems.add('$where ($id) needs a route that is a path of this application, such as /orders/new.');
        continue;
      }
      shortcuts.add(DVAppShortcut(
        id: id,
        title: title,
        route: route,
        subtitle: text('subtitle'),
        icon: text('icon'),
      ));
    }
    if (shortcuts.length > DVAppShortcut.shownByLaunchers) {
      problems.add('dartvel.appShortcuts declares ${shortcuts.length}; Android and iOS launchers '
          'show ${DVAppShortcut.shownByLaunchers}, so the rest would never appear there.');
    }
    return DVAppShortcutsConfig(List<DVAppShortcut>.unmodifiable(shortcuts),
        problems: List<String>.unmodifiable(problems));
  }
}
