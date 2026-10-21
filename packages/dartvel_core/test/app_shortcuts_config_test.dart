import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `dartvel.appShortcuts` reads the same from YAML and from a Dart config
/// class, and writes back exactly what it read.
void main() {
  const List<DVAppShortcut> declared = <DVAppShortcut>[
    DVAppShortcut(id: 'new-order', title: 'New order', route: '/orders/new', subtitle: 'Start an order'),
    DVAppShortcut(id: 'search', title: 'Search', route: '/search?focus=1', icon: 'icons/search.png'),
  ];

  test('class -> pubspec -> class is the same list', () {
    final Object pubspec = DVAppShortcutsConfig.toPubspec(declared);
    final DVAppShortcutsConfig read = DVAppShortcutsConfig.parse(pubspec);
    expect(read.problems, isEmpty);
    expect(read.shortcuts, declared);
  });

  test('YAML -> class -> pubspec is the same object, every key in place', () {
    const String yaml = '''
- id: new-order
  title: New order
  route: /orders/new
  subtitle: Start an order
- id: search
  title: Search
  route: /search?focus=1
  icon: icons/search.png
''';
    final Object? parsed = loadYaml(yaml);
    final DVAppShortcutsConfig read = DVAppShortcutsConfig.parse(parsed);
    expect(read.problems, isEmpty);
    expect(DVAppShortcutsConfig.toPubspec(read.shortcuts), <Map<String, Object?>>[
      <String, Object?>{'id': 'new-order', 'title': 'New order', 'route': '/orders/new', 'subtitle': 'Start an order'},
      <String, Object?>{'id': 'search', 'title': 'Search', 'route': '/search?focus=1', 'icon': 'icons/search.png'},
    ]);
  });

  test('unset optional keys are left out, not written as null', () {
    expect(const DVAppShortcut(id: 'a', title: 'A', route: '/a').toPubspec().keys, <String>['id', 'title', 'route']);
  });

  test('bad entries are reported and skipped, good ones kept', () {
    final DVAppShortcutsConfig read = DVAppShortcutsConfig.parse(<Object?>[
      <String, Object?>{'id': 'Bad Id', 'title': 'x', 'route': '/x'},
      <String, Object?>{'id': 'ok', 'title': 'OK', 'route': '/ok'},
      <String, Object?>{'id': 'ok', 'title': 'Again', 'route': '/again'},
      <String, Object?>{'id': 'no-title', 'route': '/x'},
      <String, Object?>{'id': 'not-a-route', 'title': 'x', 'route': 'orders'},
      <String, Object?>{'id': 'typo', 'title': 'x', 'route': '/x', 'subtitel': 'oops'},
      'not a map',
    ]);
    expect(read.shortcuts.map((DVAppShortcut s) => s.id), <String>['ok', 'typo']);
    expect(read.problems, hasLength(6));
    expect(read.problems.join('\n'), contains('unknown key "subtitel"'));
  });

  test('more than a launcher shows is a problem, and the list is kept', () {
    final DVAppShortcutsConfig read = DVAppShortcutsConfig.parse(<Object?>[
      for (int index = 0; index < 5; index++) <String, Object?>{'id': 's$index', 'title': 'S$index', 'route': '/s$index'},
    ]);
    expect(read.shortcuts, hasLength(5));
    expect(read.problems.single, contains('show 4'));
  });

  test('the launch link reaches the route with an empty host', () {
    expect(const DVAppShortcut(id: 'a', title: 'A', route: '/orders/new').launchLink, 'dartvel:///orders/new');
    expect(Uri.parse('dartvel:///orders/new').path, '/orders/new');
  });

  test('not a list is one problem', () {
    expect(DVAppShortcutsConfig.parse('nope').problems.single, contains('must be a list'));
  });
}
