// One reading of dartvel.terminal, not two that disagree.
//
// `readTerminalOptIn` refuses a value that is neither true nor false, on the
// grounds that guessing one way links a backend nobody asked for and guessing
// the other ignores a request that was made. The client generator's fallback
// tested `dv['terminal'] == true`, which quietly answers false for `yes`,
// `"true"`, `1` — and generates a main declaring a GUI surface for a project
// that asked for a terminal.
//
// `dartvel build` catches it first and exits 78, so nothing wrong ships from
// there. `dartvel routes` run by hand does not go through that check, and it
// is the same command the build runs as a subprocess.
import 'dart:io';

import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

YamlMap pubspecWith(String terminal) =>
    loadYaml('name: app\ndartvel:\n  terminal: $terminal\n') as YamlMap;

void main() {
  test('true and false are read as themselves', () {
    expect(readTerminalOptIn(pubspecWith('true')), isTrue);
    expect(readTerminalOptIn(pubspecWith('false')), isFalse);
  });

  test('a project that says nothing has not opted in', () {
    expect(readTerminalOptIn(loadYaml('name: app\n') as YamlMap), isFalse);
  });

  // The values that look like yes to a person and are not booleans to YAML.
  // Each of these refused in one reader and silently meant false in the other.
  test('a value that is neither is refused, not read as false', () {
    for (final String written in <String>['yes', '"true"', '1', 'on']) {
      expect(
        () => readTerminalOptIn(pubspecWith(written)),
        throwsA(isA<FormatException>()),
        reason: '$written was accepted as an answer',
      );
    }
  });

  // The generator has to reach the same verdict, because it is what decides
  // which main gets written. Asserted on what generation does rather than on
  // the source text -- an earlier version of this test grepped for the old
  // expression and then matched the comment explaining why it was gone.
  test('generation refuses the same values the build refuses', () async {
    final Directory root = Directory.systemTemp.createTempSync('dv_term_');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync(
      'name: app\ndartvel:\n  pagesDir: lib/pages\n  terminal: yes\n',
    );
    final File page = File('${root.path}/lib/pages/index.page.dart');
    page.parent.createSync(recursive: true);
    page.writeAsStringSync(
      "import 'package:flutter/widgets.dart';\n"
      "import 'package:dartvel_flutter/dartvel_flutter.dart';\n\n"
      "@DVPage(title: 'Home')\n"
      "Widget _homePage(BuildContext context) => const DVText('hi');\n",
    );

    final YamlMap dv = (loadYaml(
      File('${root.path}/pubspec.yaml').readAsStringSync(),
    ) as YamlMap)['dartvel'] as YamlMap;

    await expectLater(
      ClientGenerator.generate(
        root: root.path,
        pagesDir: 'lib/pages',
        pkgName: 'app',
        buildId: 'test',
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
        dv: dv,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
