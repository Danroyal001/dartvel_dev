// A lowered body needs the imports the body was written against.
//
// Body lowering moves a page's code into generated code -- its own library
// under lib/dartvel_client/pages/, which the router imports deferred so each
// page is a bundle of its own. The code came from a file with its own
// imports, and the generated file has none of them, so anything the page
// built out of its own components stopped resolving -- `Section`,
// `SiteFooter`, a design system, whatever the application layered on top of
// Dartvel.
//
// The failure is not subtle once it happens, but it is invisible until a page
// body is more than a single call: a page written as
// `=> buildHomePage(context)` lowers to one qualified call and needs nothing.
// That is exactly the shape applications were written in to work around this,
// which is why it survived.
import 'dart:io';

import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The generated router, and each lowered page body's library by file name.
typedef Generated = ({String router, Map<String, String> bodies});

Future<Generated> generatedFor(Map<String, String> files) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_lowered_imports_');
  addTearDown(() => root.deleteSync(recursive: true));

  for (final MapEntry<String, String> entry in files.entries) {
    final File file = File(p.join(root.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'imports_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://example.com',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'app',
    seoTitle: 'app',
    seoDesc: 'app',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'none',
    durationMs: 200,
    curve: 'linear',
    normalizeTrailing: true,
    notFoundRedirect: '/',
    plugins: const <String>[],
    webPrerender: false,
    ota: false,
    dv: YamlMap(),
  );

  final Directory client = Directory(p.join(root.path, 'lib', 'dartvel_client'));
  final Directory pages = Directory(p.join(client.path, 'pages'));
  return (
    router: File(p.join(client.path, 'router.g.dart')).readAsStringSync(),
    bodies: <String, String>{
      if (pages.existsSync())
        for (final File file in pages
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart')))
          p.relative(file.path, from: pages.path): file.readAsStringSync(),
    },
  );
}

/// The one body library a single-page project generates.
String onlyBody(Generated generated) {
  expect(generated.bodies, hasLength(1),
      reason: 'one lowered page, one body library: ${generated.bodies.keys}');
  return generated.bodies.values.single;
}

const String _component = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class Banner_ extends StatelessWidget {
  const Banner_(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => DVText(text);
}
''';

const String _bannerImport =
    r"import 'package:imports_app/components/banner\.dart'";

void main() {
  test('a component the page imports is imported where the body lands',
      () async {
    final String body = onlyBody(await generatedFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget _homePage(BuildContext context) => const Banner_('hi');\n",
    }));

    // The body is lowered, so the symbol has to resolve where it landed.
    expect(body, contains("Banner_('hi')"));
    expect(body, contains('package:imports_app/components/banner.dart'));
  });

  test('the import is not deferred, so a const body still compiles', () async {
    // The body's library is itself reached through a deferred import, for
    // code splitting, and a const expression may not name a type from a
    // deferred import. So within that library the component's import must be
    // an ordinary one: lowering `const Banner_(...)` through a deferred alias
    // produces "Not a constant expression" -- which is what this failed with.
    final String body = onlyBody(await generatedFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget _homePage(BuildContext context) => const Banner_('hi');\n",
    }));

    final RegExpMatch? match = RegExp('$_bannerImport([^;]*);').firstMatch(body);
    expect(match, isNotNull);
    expect(match!.group(1), isNot(contains('deferred')));
  });

  test('a relative import becomes a package URI', () async {
    // The generated files live under lib/dartvel_client, so '../components/x'
    // is a different directory from there. Copied across as written it
    // resolves to nothing, or worse, to something else.
    final Generated generated = await generatedFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget _homePage(BuildContext context) => const Banner_('hi');\n",
    });

    for (final String file in <String>[
      generated.router,
      ...generated.bodies.values,
    ]) {
      expect(file, isNot(contains("import '../components/banner.dart'")));
    }
    expect(onlyBody(generated), contains('package:imports_app/components/'));
  });

  test('two pages importing the same component import it once each',
      () async {
    final Generated generated = await generatedFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget _homePage(BuildContext context) => const Banner_('a');\n",
      'lib/pages/about.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'About')\n"
          "Widget _aboutPage(BuildContext context) => const Banner_('b');\n",
    });

    expect(generated.bodies, hasLength(2));
    for (final MapEntry<String, String> body in generated.bodies.entries) {
      expect(RegExp(_bannerImport).allMatches(body.value), hasLength(1),
          reason: '${body.key}: a duplicate import will not compile');
    }
  });

  test('a page that is not lowered does not drag its imports in', () async {
    // A public page is called rather than inlined, so its imports stay its
    // own. Copying them anyway would put every application file into
    // generated code the router reaches and defeat the code splitting the
    // deferred imports exist for.
    final Generated generated = await generatedFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget homePage(BuildContext context) => const Banner_('hi');\n",
    });

    for (final String file in <String>[
      generated.router,
      ...generated.bodies.values,
    ]) {
      expect(file,
          isNot(contains('package:imports_app/components/banner.dart')));
    }
  });
}
