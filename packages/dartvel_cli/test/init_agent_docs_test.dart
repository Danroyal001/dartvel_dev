// A project that adopts Dartvel gets the agent rules `dartvel create` writes.
//
// `dartvel init` adds the dependency and the `dartvel:` key and stops there,
// which was the point: adopting a framework should not rewrite somebody's
// project. But a project on Dartvel with no rules file is read by whichever
// agent happens to be opened, and every tool wants a differently named file,
// so half an adoption is what it got. These are additive files with a
// generated block, and a file the project already had keeps its own text.
import 'dart:io';

import 'package:dartvel_cli/src/agents/agent_docs.dart';
import 'package:dartvel_cli/src/commands/adopt_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late List<String> out;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_init_agents_');
    out = <String>[];
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  void write(String relative, String content) {
    final File file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String read(String relative) =>
      File(p.join(root.path, relative)).readAsStringSync();

  group('init', () {
    test('writes the agent files and says which', () async {
      write('pubspec.yaml', '''
name: adopted
publish_to: none
environment:
  sdk: ^3.13.0
''');

      final int code = await dvRunInit(
        root.path,
        dryRun: false,
        assumeYes: true,
        interactive: false,
        confirm: () async => true,
        out: out.add,
      );

      expect(code, 0);
      expect(File(p.join(root.path, 'AGENTS.md')).existsSync(), isTrue);
      expect(File(p.join(root.path, '.cursor/rules/dartvel.mdc')).existsSync(),
          isTrue);
      expect(out.join('\n'), contains('Agent rules set up'));
    });

    test('a dry run says what it would set up and writes nothing', () async {
      write('pubspec.yaml', '''
name: adopted
publish_to: none
environment:
  sdk: ^3.13.0
''');

      final int code = await dvRunInit(
        root.path,
        dryRun: true,
        assumeYes: true,
        interactive: false,
        confirm: () async => true,
        out: out.add,
      );

      expect(code, 0);
      expect(File(p.join(root.path, 'AGENTS.md')).existsSync(), isFalse);
    });

    test('a CLAUDE.md the project already wrote keeps its own text', () async {
      write('pubspec.yaml', '''
name: adopted
publish_to: none
environment:
  sdk: ^3.13.0
''');
      write('CLAUDE.md', '# Our conventions\n\nAlways run the linter first.\n');

      await dvRunInit(
        root.path,
        dryRun: false,
        assumeYes: true,
        interactive: false,
        confirm: () async => true,
        out: out.add,
      );

      expect(read('CLAUDE.md'), contains('Always run the linter first.'));
      expect(read('CLAUDE.md'), contains(dvAgentBlockBegin));
    });
  });
}