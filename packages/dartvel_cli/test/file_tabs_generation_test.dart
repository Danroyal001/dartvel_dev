// Tabs from files, the generated DVRouter, and mounting into a host router.
//
// A `_layout.dart` whose class extends DartvelTabsLayout makes its folder a
// StatefulShellRoute: one branch per tab it names, each page in a branch
// nested under the one whose path it extends, so a detail page is pushed
// over its list inside the tab rather than replacing it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pubspec = '''
name: tabs_probe
publish_to: none
environment:
  sdk: ^3.12.0
dartvel:
  prodBackendHost: https://example.com
''';

String _page(String name, {String depth = '../'}) =>
    '''
import 'package:flutter/widgets.dart';
import '${depth}dartvel_client/dartvel_client.dart';

@DVPage(title: '$name')
@pragma('vm:entry-point')
Widget _${name}Page(BuildContext context) => const DVText('$name');
''';

String _tabsLayout(String tabs) =>
    '''
import 'package:flutter/widgets.dart';
import '../../dartvel_client/dartvel_client.dart';

class AppTabs extends DartvelTabsLayout {
  const AppTabs({super.key, required super.shell});

  static const List<DVRouteTarget> tabs = <DVRouteTarget>[$tabs];

  @override
  Widget build(BuildContext context) => shell;
}
''';

late Directory root;

void write(String rel, String contents) {
  File(p.join(root.path, rel))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

String router() => File(
  p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
).readAsStringSync();

Future<Object?> generateError() async {
  try {
    await routes.generate(root_: root.path);
  } on Object catch (e) {
    return e;
  }
  return null;
}

void main() {
  setUp(() async {
    root = await Directory.systemTemp.createTemp('dartvel_file_tabs_');
    write('pubspec.yaml', _pubspec);
    write('lib/pages/index.page.dart', _page('index'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('a tabs layout', () {
    setUp(() {
      write(
        'lib/pages/(tabs)/_layout.dart',
        _tabsLayout('DVRoutes.feed, DVRoutes.saved'),
      );
      write(
        'lib/pages/(tabs)/feed/index.page.dart',
        _page('feed', depth: '../../../'),
      );
      write(
        'lib/pages/(tabs)/feed/[post].page.dart',
        _page('post', depth: '../../../'),
      );
      write(
        'lib/pages/(tabs)/saved.page.dart',
        _page('saved', depth: '../../'),
      );
    });

    test('makes its folder a StatefulShellRoute built by the layout', () async {
      await routes.generate(root_: root.path);
      final String source = router();

      expect(source, contains('StatefulShellRoute.indexedStack('));
      expect(source, contains('AppTabs(shell: dvShellNavigation(shell))'));
      // Branches in the order the layout names them.
      final int shell = source.indexOf('StatefulShellRoute.indexedStack(');
      final int feed = source.indexOf("path: '/feed'", shell);
      final int saved = source.indexOf("path: '/saved'", shell);
      expect(feed, greaterThan(shell));
      expect(saved, greaterThan(feed));
    });

    test(
      'nests a detail page under its list, relative, inside the tab',
      () async {
        await routes.generate(root_: root.path);
        final String all = router();
        final String source = all.substring(0, all.indexOf('class DVRoutes'));
        final int feed = source.indexOf("path: '/feed'");
        final int post = source.indexOf("path: ':post'");

        expect(post, greaterThan(feed));
        expect(source, isNot(contains("path: '/feed/:post'")));
        // A pushed page carries the platform's back gesture.
        expect(source, contains('MaterialPage<void>(key: state.pageKey'));
      },
    );

    test('names a detail page beside its list instead of colliding', () async {
      await routes.generate(root_: root.path);
      final String source = router();

      expect(source, contains("static const feed = DVRouteTarget('/feed');"));
      expect(
        source,
        contains(
          "static DVRouteTarget feedPost({required String post}) => "
          "DVRouteTarget('/feed/\$post');",
        ),
      );
      final String manifest = source.substring(
        source.indexOf('dartvelRouteManifest'),
      );
      expect(manifest, contains("path: '/feed/:post',"));
    });

    test('is not also wrapped around each page as a layout', () async {
      await routes.generate(root_: root.path);
      final String source = router();
      expect(source, isNot(contains('AppTabs(child:')));
    });

    test('DV-ROUTE-005: a tab that is no page in the folder', () async {
      write(
        'lib/pages/(tabs)/_layout.dart',
        _tabsLayout('DVRoutes.feed, DVRoutes.index'),
      );
      final Object? error = await generateError();
      expect(error.toString(), contains('DV-ROUTE-005'));
      expect(error.toString(), contains('DVRoutes.index'));
    });

    test('DV-ROUTE-005: a page in the folder under no tab', () async {
      write(
        'lib/pages/(tabs)/stray.page.dart',
        _page('stray', depth: '../../'),
      );
      final Object? error = await generateError();
      expect(error.toString(), contains('DV-ROUTE-005'));
      expect(error.toString(), contains('/stray'));
    });
  });

  group('the generated router', () {
    test('is a DVRouter, so a pending first location is never blank', () async {
      await routes.generate(root_: root.path);
      expect(router(), contains('final router = DVRouter('));
    });

    test('offers its routes to a host GoRouter, at a mount point', () async {
      await routes.generate(root_: root.path);
      final String source = router();

      expect(
        source,
        contains(
          "List<RouteBase> dartvelRoutes({String at = '/', "
          'List<String> arguments = const <String>[]})',
        ),
      );
      expect(source, contains('dvMountRoutes(_dartvelRouteList(), at: at)'));
      expect(source, contains('routes: _dartvelRouteList(),'));
    });
  });
}
