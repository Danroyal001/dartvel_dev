// The router a `dart run build_runner build` writes: a lowered page's body is
// called, never copied.
//
// Every page is imported `deferred` so that main.dart.js carries the shell and
// a page's code arrives when its loadLibrary() runs. The router copied each
// private page's body into itself, and the router is eager: everything the
// body built was then reachable from main(), dart2js put it in main.dart.js,
// and the deferred import was left guarding a few constants. `dartvel routes`
// stopped doing that in 5145f509; this is the same for build_runner, which
// basic_app and class_widgets_app build with.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dartvel_generator/dartvel_generator.dart';
import 'package:test/test.dart';

const String pubspec = '''
name: a
dartvel:
  pagesDir: lib/pages
''';

/// A private, expression-bodied page: the kind that is lowered.
const String loweredPage = r"""
import 'package:a/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import '../components/banner.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => DVBox.list([
      const Banner('Welcome'),
      DVText('x').modifier(titleStyle),
    ]);

final titleStyle = const DVModifier().padding(8);
""";

/// A public class page: not lowered, and imported as it always was.
const String classPage = r"""
import 'package:a/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(title: 'About')
class AboutPage extends DartvelPage {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) => const DVText('About');
}
""";

Future<String> router(Map<String, String> pages) async {
  final TestBuilderResult result = await testBuilder(
    routerBuilder(BuilderOptions.empty),
    <String, String>{'a|pubspec.yaml': pubspec, ...pages},
    rootPackage: 'a',
  );
  const String router = 'lib/dartvel_client/router.g.dart';
  expect(result.outputs, contains(AssetId('a', router)));
  // Where the file is, not where it is named: under testBuilder an output
  // lands in the build cache, the same fallback build_test's own checkOutputs
  // uses.
  for (final AssetId id in <AssetId>[
    AssetId('a', router),
    AssetId('a', '.dart_tool/build/generated/a/$router'),
  ]) {
    if (result.readerWriter.testing.exists(id)) {
      return result.readerWriter.testing.readString(id);
    }
  }
  fail('router.g.dart was written and cannot be found');
}

void main() {
  group('a lowered page', () {
    late String source;
    setUp(() async {
      source = await router(<String, String>{
        'a|lib/pages/index.dart': loweredPage,
      });
    });

    test('is reached through its body library, deferred', () {
      expect(
        source,
        contains("import 'package:a/dartvel_client/pages/pages/index.g.dart' "
            'deferred as p0;'),
      );
    });

    test('whose body the router calls', () {
      expect(source, contains('return p0.dvPageBody(context);'));
    });

    test('and does not copy, so nothing it builds is reachable from main()',
        () {
      expect(source, isNot(contains('DVBox.list(')));
      expect(source, isNot(contains('Banner(')));
      expect(source, isNot(contains('titleStyle')));
    });

    test('the page file itself is not imported by the router at all', () {
      // Imported here eagerly or deferred, it would be a second way to reach
      // the page's code; the body library is the only one.
      expect(source, isNot(contains("import 'package:a/pages/index.dart'")));
    });
  });

  test('a class page is imported deferred, as it always was', () async {
    final String source = await router(<String, String>{
      'a|lib/pages/about.dart': classPage,
    });
    expect(source, contains("import 'package:a/pages/about.dart' deferred as p0;"));
    expect(source, contains('p0.AboutPage()'));
  });

  test('a link can preload each page, in the shape the build reads', () async {
    final String source = await router(<String, String>{
      'a|lib/pages/index.dart': loweredPage,
    });
    // `dartvel build web` reads this pair to tell which deferred import a
    // route loads, and DVNavLink preloads through the registration. Without
    // it no link in a build_runner application preloaded anything.
    final RegExpMatch? registration = RegExp(
      r"  DVRoutePreloaders\.register\(\n    '/',\n    (\w+)\.loadLibrary,\n  \);",
    ).firstMatch(source);
    expect(registration, isNotNull, reason: source);
    final String page = registration!.group(1)!;
    expect(
      RegExp('class $page extends DartvelPage \\{[\\s\\S]*?'
              r'_libraryFuture \?\?= p0\.loadLibrary\(\);')
          .hasMatch(source),
      isTrue,
    );
  });
}
