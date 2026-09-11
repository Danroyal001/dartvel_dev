// Each lowered page's body, written by build_runner into a library of its own.
//
// The router imports this library `deferred` and nothing else reaches it, so
// on the web the page's code is a part that its loadLibrary() fetches. The
// router builder cannot write it: its inputs are the pubspec and its outputs
// are fixed, while this is one file per page. So a builder of its own, keyed
// on the page file.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dartvel_generator/dartvel_generator.dart';
import 'package:test/test.dart';

const String pubspec = '''
name: a
dartvel:
  pagesDir: lib/pages
''';

const String loweredPage = r"""
import 'package:a/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import '../components/banner.dart';
import '../components/charts.dart' deferred as charts;

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => DVBox.list([
      const Banner('Welcome'),
      DVText('x').modifier(titleStyle),
    ]);

final titleStyle = const DVModifier().padding(8);
""";

const String body = 'lib/dartvel_client/pages/pages/index.g.dart';

Future<TestBuilderResult> run(
  Map<String, String> sources, {
  String project = pubspec,
}) =>
    testBuilder(
      pageBodyBuilder(BuilderOptions.empty),
      <String, String>{'a|pubspec.yaml': project, ...sources},
      rootPackage: 'a',
    );

bool wrote(TestBuilderResult result, String path) =>
    result.outputs.contains(AssetId('a', path));

/// Where the file is, not where it is named: under testBuilder an output
/// lands in the build cache, the same fallback build_test's own checkOutputs
/// uses.
String read(TestBuilderResult result, String path) {
  for (final AssetId id in <AssetId>[
    AssetId('a', path),
    AssetId('a', '.dart_tool/build/generated/a/$path'),
  ]) {
    if (result.readerWriter.testing.exists(id)) {
      return result.readerWriter.testing.readString(id);
    }
  }
  fail('$path was written and cannot be found');
}

void main() {
  group('a lowered page', () {
    late String library;
    setUp(() async {
      final TestBuilderResult result =
          await run(<String, String>{'a|lib/pages/index.dart': loweredPage});
      expect(wrote(result, body), isTrue, reason: 'no body library written');
      library = read(result, body);
    });

    test('gets its body as a function of its own library', () {
      expect(library, contains('Widget dvPageBody(BuildContext context) {'));
      expect(library, contains('return DVBox.list(['));
      expect(library, contains("const Banner('Welcome')"));
    });

    test('which reaches what stayed in the page through an alias', () {
      // The body was written in the page's library, where titleStyle is in
      // scope. Here it is not, so it is qualified -- as the router's copy was.
      expect(
        library,
        contains("import 'package:a/pages/index.dart' as dv_page_source;"),
      );
      expect(library, contains('dv_page_source.titleStyle'));
    });

    test('and the page\'s own imports, a relative one as a package URI', () {
      // Relative to lib/pages, `../components/banner.dart` is right; from
      // lib/dartvel_client/pages/pages it names nothing.
      expect(library, contains("import 'package:a/components/banner.dart';"));
      expect(
        library,
        contains("import 'package:a/dartvel_client/dartvel_client.dart';"),
      );
      expect(library, contains("import 'package:flutter/material.dart';"));
    });

    test('imports nothing deferred, so a const in the body still compiles', () {
      // A const expression cannot name a type through a deferred prefix.
      // The library itself is only reached deferred, which is what splits it.
      // The page imports charts.dart deferred; the body library must not.
      expect(library, isNot(contains('charts.dart')));
      expect(
        RegExp(r'^import .*\bdeferred\b', multiLine: true).hasMatch(library),
        isFalse,
      );
    });
  });

  test('a page directory of the project\'s own choosing', () async {
    final TestBuilderResult result = await run(
      <String, String>{'a|lib/screens/home.dart': loweredPage},
      project: 'name: a\ndartvel:\n  pagesDir: lib/screens\n',
    );
    expect(wrote(result, 'lib/dartvel_client/pages/screens/home.g.dart'),
        isTrue);
  });

  group('nothing is written for', () {
    Future<void> expectNothing(Map<String, String> sources,
        {String project = pubspec}) async {
      final TestBuilderResult result = await run(sources, project: project);
      expect(
        result.readerWriter.testing.assetsWritten
            .where((AssetId id) => id.path.startsWith('lib/dartvel_client/')),
        isEmpty,
      );
    }

    test('a class page, which is imported as it is', () {
      return expectNothing(<String, String>{
        'a|lib/pages/about.dart': '''
@DVPage(title: 'About')
class AboutPage extends DartvelPage {
  const AboutPage({super.key});
}
''',
      });
    });

    test('a public function page, which the router calls where it is', () {
      return expectNothing(<String, String>{
        'a|lib/pages/about.dart': '''
@DVPage(title: 'About')
Widget aboutPage(BuildContext context) => const DVText('About');
''',
      });
    });

    test('a file outside the pages directory', () {
      return expectNothing(
          <String, String>{'a|lib/components/index.dart': loweredPage});
    });

    test('a layout, a guard, a loading or an error page', () {
      return expectNothing(<String, String>{
        'a|lib/pages/_layout.dart': loweredPage,
        'a|lib/pages/_guard.dart': loweredPage,
        'a|lib/pages/index.loading.dart': loweredPage,
        'a|lib/pages/index.error.dart': loweredPage,
      });
    });

    test('a project that is not a Dartvel one', () {
      return expectNothing(
        <String, String>{'a|lib/pages/index.dart': loweredPage},
        project: 'name: a\n',
      );
    });
  });
}
