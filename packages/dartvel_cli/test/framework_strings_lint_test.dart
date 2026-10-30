// DV-STATE-003: a framework string is a literal rather than an i18n key.
//
// Error, Empty, and Loading States promises that the words Dartvel's own
// widgets say localise and rebrand like everything else an application says.
// A literal in a widget is the silent failure of that promise: the English
// reads as a plausible rendering in every locale, so nothing looks broken and
// a French application keeps saying "Page not found". The check reads the
// source lexically, as the tooltip rule does, and reports each literal with
// its file and line.
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/analysis/framework_strings_lint.dart';
import 'package:dartvel_cli/src/commands/analyze_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

List<DVFrameworkStringFinding> lint(String source) =>
    dvFindLiteralFrameworkStrings(path: 'lib/x.dart', source: source);

Future<String> runAnalyze(List<String> args, Directory root) async {
  final StringBuffer out = StringBuffer();
  await runZoned(
    () async {
      final CommandRunner<void> runner =
          CommandRunner<void>('dartvel', 'Test runner')
            ..addCommand(AnalyzeCommand(root: root.path));
      await runner.run(<String>['analyze', ...args]);
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone _, ZoneDelegate __, Zone ___, String line) =>
          out.writeln(line),
    ),
  );
  return out.toString();
}

void main() {
  group('a literal a widget says', () {
    test('as the text of a Text or DVText is reported with its line', () {
      final List<DVFrameworkStringFinding> found = lint('''
Widget a() => Column(children: [
  const Text('Page not found'),
  DVText("Try again"),
]);
''');
      expect(found.map((DVFrameworkStringFinding f) => f.line), <int>[2, 3]);
      expect(found.first.code, 'DV-STATE-003');
      expect(found.first.text, 'Page not found');
      expect(found.first.toString(), contains('lib/x.dart:2'));
      expect(found.first.toString(), contains('DV-STATE-003'));
    });

    test('as a label, hint, tooltip or semantic label is reported', () {
      final List<DVFrameworkStringFinding> found = lint('''
Widget a() => Column(children: [
  TextField(decoration: InputDecoration(labelText: 'Email', hintText: 'you@example.com')),
  Semantics(label: 'Loading', child: x),
  IconButton(tooltip: 'Close', onPressed: go, icon: i),
  DVBox(i, DVModifier().tooltip('Delete').onTap(go)),
  Breadcrumb(label: 'Home', path: '/'),
]);
''');
      expect(found.map((DVFrameworkStringFinding f) => f.text), <String>[
        'Email',
        'you@example.com',
        'Loading',
        'Close',
        'Delete',
        'Home',
      ]);
    });

    test('with interpolation still counts when words surround the values', () {
      final List<DVFrameworkStringFinding> found =
          lint(r"Semantics(label: '${c.label}, $text, row ${r + 1} of $n');");
      expect(found, hasLength(1));
    });

    test('adjacent literals are one string, reported once', () {
      final List<DVFrameworkStringFinding> found = lint('''
const DVText('This application would like '
    'your permission.');
''');
      expect(found, hasLength(1));
      expect(found.single.text,
          'This application would like your permission.');
    });
  });

  group('what is not a framework string', () {
    test('a key read through DV.I18n passes', () {
      expect(
        lint('Text(DV.I18n.t(DVFrameworkStrings.retry));'),
        isEmpty,
      );
    });

    test('a value passed through with no words of its own passes', () {
      expect(lint(r"MenuItem(tooltip: '${map['tooltip'] ?? ''}');"), isEmpty);
      expect(lint(r"Semantics(label: '$label, $state');"), isEmpty);
      expect(lint("Text('?');"), isEmpty);
      expect(lint("DVText('');"), isEmpty);
    });

    test('a string in a comment or a doc comment is not read', () {
      expect(
        lint('''
/// Shows `Text('Page not found')` to the reader.
// Text('Old copy')
Widget a() => x;
'''),
        isEmpty,
      );
    });

    test('a word that only ends in label is not the label argument', () {
      expect(lint("Thing(debugLabel: 'DVLinkButton');"), isEmpty);
    });

    test('a message a developer reads in a log is not a widget string', () {
      expect(lint("DVFinding(message: 'every open degraded');"), isEmpty);
    });
  });

  group('scanning a package', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_state_003_');
      File(p.join(root.path, 'pubspec.yaml'))
          .writeAsStringSync('name: strings_pkg\n');
      Directory(p.join(root.path, 'lib', 'src', 'tools'))
          .createSync(recursive: true);
      File(p.join(root.path, 'lib', 'src', 'page.dart'))
          .writeAsStringSync("Widget a() => const Text('Nothing here');\n");
      File(p.join(root.path, 'lib', 'src', 'tools', 'dev.dart'))
          .writeAsStringSync("Widget b() => const Text('Developer only');\n");
      File(p.join(root.path, 'lib', 'src', 'page.g.dart'))
          .writeAsStringSync("Widget c() => const Text('Generated');\n");
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('reads lib/, skips generated code, and honours exclusions', () {
      expect(
        dvScanForLiteralFrameworkStrings(root.path)
            .map((DVFrameworkStringFinding f) => f.path),
        <String>[p.join('lib', 'src', 'page.dart'), p.join('lib', 'src', 'tools', 'dev.dart')],
      );
      expect(
        dvScanForLiteralFrameworkStrings(
          root.path,
          exclude: <String>['lib/src/tools/'],
        ).map((DVFrameworkStringFinding f) => f.path),
        <String>[p.join('lib', 'src', 'page.dart')],
      );
    });

    test('dartvel analyze strings prints each finding as a warning', () async {
      final String out = await runAnalyze(<String>['strings'], root);
      expect(out, contains('DV-STATE-003'));
      expect(out, contains('lib/src/page.dart:1'));
      expect(out, contains('Nothing here'));
      expect(out, contains('2 framework string(s)'));
    });

    test('a package with none says so', () async {
      final String out = await runAnalyze(
        <String>['strings', '--exclude', 'lib/'],
        root,
      );
      expect(out, contains('no framework string is a literal'));
    });
  });

  group("dartvel_flutter's own widgets", () {
    // The developer tools -- Studio, the admin screens, the dev client and the
    // docs viewer -- are read by the person building the application, not by
    // its readers, and are English by design. Everything else a Dartvel widget
    // shows reaches an application's readers, so it is held to zero.
    test('say nothing as a literal outside the developer tools', () {
      final String flutter = p.normalize(
        p.join(Directory.current.path, '..', 'dartvel_flutter'),
      );
      final List<DVFrameworkStringFinding> found =
          dvScanForLiteralFrameworkStrings(
        flutter,
        exclude: dvDeveloperToolDirectories,
      );
      expect(found.map((DVFrameworkStringFinding f) => f.toString()).toList(),
          isEmpty);
    });
  });
}
