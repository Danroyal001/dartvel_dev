// A lowered body needs the imports the body was written against.
//
// Body lowering moves a page's code into the generated router. The code came
// from a file with its own imports, and the generated file has none of them,
// so anything the page built out of its own components stopped resolving --
// `Section`, `SiteFooter`, a design system, whatever the application layered
// on top of Dartvel.
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

Future<String> routerFor(Map<String, String> files) async {
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

  return File(p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'))
      .readAsStringSync();
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

void main() {
  test('a component the page imports is imported by the generated router',
      () async {
    final String router = await routerFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget _homePage(BuildContext context) => const Banner_('hi');\n",
    });

    // The body is lowered, so the symbol has to resolve where it landed.
    expect(router, contains("Banner_('hi')"));
    expect(router, contains('package:imports_app/components/banner.dart'));
  });

  test('the import is not deferred, so a const body still compiles', () async {
    // Page files are imported deferred, for code splitting. A const expression
    // may not name a type from a deferred import, so lowering a body that says
    // `const Banner_(...)` through a deferred alias produces "Not a constant
    // expression" -- which is what this failed with.
    final String router = await routerFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget _homePage(BuildContext context) => const Banner_('hi');\n",
    });

    final RegExp bannerImport = RegExp(
      r"import 'package:imports_app/components/banner\.dart'([^;]*);",
    );
    final RegExpMatch? match = bannerImport.firstMatch(router);
    expect(match, isNotNull);
    expect(match!.group(1), isNot(contains('deferred')));
  });

  test('a relative import becomes a package URI', () async {
    // The generated file lives in lib/dartvel_client, so '../components/x' is
    // a different directory from there. Copied across as written it resolves
    // to nothing, or worse, to something else.
    final String router = await routerFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget _homePage(BuildContext context) => const Banner_('hi');\n",
    });

    expect(router, isNot(contains("import '../components/banner.dart'")));
  });

  test('two pages importing the same component import it once', () async {
    final String router = await routerFor(<String, String>{
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

    final int occurrences =
        RegExp(r"import 'package:imports_app/components/banner\.dart'")
            .allMatches(router)
            .length;
    expect(occurrences, 1, reason: 'a duplicate import will not compile');
  });

  test('a page that is not lowered does not drag its imports in', () async {
    // A public page is called rather than inlined, so its imports stay its
    // own. Copying them anyway would put every application file into the
    // generated router and defeat the code splitting the deferred imports
    // exist for.
    final String router = await routerFor(<String, String>{
      'lib/components/banner.dart': _component,
      'lib/pages/index.page.dart': "import 'package:flutter/widgets.dart';\n"
          "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
          "import '../components/banner.dart';\n"
          "@DVPage(title: 'Home')\n"
          "Widget homePage(BuildContext context) => const Banner_('hi');\n",
    });

    expect(router, isNot(contains('package:imports_app/components/banner.dart')));
  });
}
