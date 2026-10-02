// Every coding agent a Dartvel project is set up for, from one source.
//
// A new project had no agent documentation at all: `dartvel create` wrote a
// README and nothing else, so whichever agent you opened the project in read
// whatever it happened to infer, and eleven tools each wanted a differently
// named file to be told the same thing. Next.js 16.3 solved the version half
// of this -- `next dev` keeps a block in AGENTS.md matched to the installed
// package -- and this is the same answer for Dartvel: one generated block, one
// source, refreshed by `dartvel dev`.
//
// The tests below are about behaviour a project can observe: which files
// exist, that they carry the block, that a project's own text survives a
// refresh, and that a refresh nobody needed changes nothing. They deliberately
// do not assert the exact prose of the block, because prose is not the
// contract; what has to hold is that every file says the same thing about the
// installed version.
import 'dart:io';

import 'package:dartvel_cli/src/agents/agent_docs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _rules = '''
# Dartvel rules for this project

- Import the generated barrel.
- Write through data models, never through a record or a query.
''';

void main() {
  late Directory root;
  late List<DVAgentDocWrite> plan;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_agent_docs_');
    addTearDown(() => root.deleteSync(recursive: true));
    plan = dvPlanAgentDocs(
      root: root.path,
      projectName: 'probe',
      version: '0.9.4',
      rules: _rules,
      docsPath: '/home/pub-cache/dartvel_cli-0.9.4/docs',
    );
  });

  String read(String relative) =>
      File(p.join(root.path, relative)).readAsStringSync();

  group('one source, every agent', () {
    test('the plan writes the canonical file and every tool that asks for its'
        ' own', () {
      final Set<String> paths =
          plan.map((DVAgentDocWrite w) => w.path).toSet();

      expect(
        paths,
        containsAll(<String>[
          'AGENTS.md',
          'CLAUDE.md',
          'GEMINI.md',
          'AGENT.md',
          'CONVENTIONS.md',
          '.cursorrules',
          '.cursor/rules/dartvel.mdc',
          '.windsurfrules',
          '.clinerules',
          '.kiro/steering/dartvel.md',
          '.github/copilot-instructions.md',
          '.aider.conf.yml',
        ]),
      );
    });

    test('the canonical file names the tools that read it with no file of'
        ' their own', () {
      // Codex, OpenCode, Devin and ChatGPT read AGENTS.md from the project
      // root. Writing a second copy for each would be four more files that can
      // disagree; the block says which tools it serves instead, so a tool that
      // is missing is visible in one place.
      final DVAgentDocTarget canonical = dvAgentDocTargets()
          .firstWhere((DVAgentDocTarget t) => t.path == 'AGENTS.md');

      expect(canonical.tools, containsAll(<String>['Codex', 'OpenCode', 'Devin']));
    });

    test('every rule file carries the same block, so no two can disagree', () {
      dvApplyAgentDocs(plan);

      for (final DVAgentDocTarget target in dvAgentDocTargets()) {
        if (target.kind != DVAgentDocKind.rules) continue;
        final String body = read(target.path);
        expect(body, contains(dvAgentBlockBegin),
            reason: '${target.path} has no managed block');
        expect(
          body.substring(body.indexOf(dvAgentBlockBegin), body.indexOf(dvAgentBlockEnd)),
          read('AGENTS.md').substring(
              read('AGENTS.md').indexOf(dvAgentBlockBegin),
              read('AGENTS.md').indexOf(dvAgentBlockEnd)),
          reason: '${target.path} says something different from AGENTS.md',
        );
      }
    });

    test('the block names the installed version and the docs shipped with it',
        () {
      dvApplyAgentDocs(plan);
      final String block = dvAgentBlock(
        version: '0.9.4',
        rules: _rules,
        docsPath: '/home/pub-cache/dartvel_cli-0.9.4/docs',
      );

      expect(read('AGENTS.md'), contains(block));
      expect(block, contains('0.9.4'));
      expect(block, contains('/home/pub-cache/dartvel_cli-0.9.4/docs'));
    });

    test('the canonical file says which project it is written for', () {
      // An agent opening the project should not have to read pubspec.yaml to
      // learn what it is in, and a rules file for "this project" that never
      // names the project reads like a template nobody filled in.
      dvApplyAgentDocs(plan);

      expect(read('AGENTS.md'), contains('probe'));
    });

    test("Cursor's rules file keeps the frontmatter Cursor needs to apply it",
        () {
      dvApplyAgentDocs(plan);
      final String body = read('.cursor/rules/dartvel.mdc');

      expect(body, startsWith('---\n'));
      expect(body, contains('alwaysApply: true'));
      expect(body.indexOf(dvAgentBlockBegin), greaterThan(body.indexOf('---')));
    });

    test("aider is configured rather than handed markdown it would ignore", () {
      dvApplyAgentDocs(plan);
      final String config = read('.aider.conf.yml');

      // `.aider.conf.yml` is YAML. Markdown in it is a parse error, and the
      // file this repository already uses points aider at CONVENTIONS.md.
      expect(config, isNot(contains('#')));
      expect(config, contains('AGENTS.md'));
    });
  });

  group('a refresh keeps what the project wrote', () {
    test('text above and below the block survives', () {
      dvApplyAgentDocs(plan);
      final File agents = File(p.join(root.path, 'AGENTS.md'));
      agents.writeAsStringSync(
        '# Our house rules\n\nDo not merge without a review.\n\n'
        '${dvAgentBlock(version: '0.9.4', rules: _rules)}\n\n'
        '## Deployment\n\nAsk before deploying.\n',
      );

      final List<DVAgentDocWrite> refreshed = dvPlanAgentDocs(
        root: root.path,
        projectName: 'probe',
        version: '0.9.5',
        rules: _rules,
        docsPath: '/home/pub-cache/dartvel_cli-0.9.5/docs',
      );
      dvApplyAgentDocs(refreshed);

      final String body = agents.readAsStringSync();
      expect(body, contains('Do not merge without a review.'));
      expect(body, contains('Ask before deploying.'));
      expect(body, contains('0.9.5'));
      expect(body, isNot(contains('0.9.4')));
    });

    test('a version behind is reported, not silently kept', () {
      dvApplyAgentDocs(plan);
      File(p.join(root.path, 'CLAUDE.md')).writeAsStringSync(
        '${dvAgentBlock(version: '0.9.1', rules: _rules)}\n',
      );

      final DVAgentDocWrite stale = dvPlanAgentDocs(
        root: root.path,
        projectName: 'probe',
        version: '0.9.4',
        rules: _rules,
        docsPath: '/home/pub-cache/dartvel_cli-0.9.4/docs',
      ).firstWhere((DVAgentDocWrite w) => w.path == 'CLAUDE.md');

      expect(stale.action, DVAgentDocAction.updated);
    });

    test('a file deleted by hand comes back, because create set the agent up',
        () {
      dvApplyAgentDocs(plan);
      File(p.join(root.path, 'GEMINI.md')).deleteSync();

      final DVAgentDocWrite restored = dvPlanAgentDocs(
        root: root.path,
        projectName: 'probe',
        version: '0.9.4',
        rules: _rules,
        docsPath: '/home/pub-cache/dartvel_cli-0.9.4/docs',
      ).firstWhere((DVAgentDocWrite w) => w.path == 'GEMINI.md');

      expect(restored.action, DVAgentDocAction.created);
    });
  });

  group('a refresh nobody needed touches nothing', () {
    test('a second pass reports every file unchanged and writes no bytes', () {
      dvApplyAgentDocs(plan);

      final List<DVAgentDocWrite> again = dvPlanAgentDocs(
        root: root.path,
        projectName: 'probe',
        version: '0.9.4',
        rules: _rules,
        docsPath: '/home/pub-cache/dartvel_cli-0.9.4/docs',
      );

      expect(again.every((DVAgentDocWrite w) => w.action == DVAgentDocAction.unchanged),
          isTrue,
          reason: again
              .where((DVAgentDocWrite w) => w.action != DVAgentDocAction.unchanged)
              .map((DVAgentDocWrite w) => w.path)
              .join(', '));
      expect(dvApplyAgentDocs(again), isEmpty);
    });
  });

  group('the docs the block points at', () {
    test('are the ones shipped with the installed Dartvel', () async {
      final String? rules = await dvBundledAgentRules();

      expect(rules, isNotNull,
          reason: 'dartvel_cli ships the rules the block quotes; without them '
              'the block can only be a promise');
      expect(rules!.trim(), isNotEmpty);
    });

    test('are absent from a project rather than invented', () {
      // An installed Dartvel with no docs beside it still gets working agent
      // files; the block then names the command that builds the project's own
      // reference instead of a path that does not exist.
      final String block = dvAgentBlock(version: '0.9.4', rules: _rules);

      expect(block, isNot(contains('docs/')));
      expect(block, contains('dartvel docs'));
    });
  });

  group('sync is what `dartvel dev` runs', () {
    test('it writes the files, then reports what it changed', () async {
      final DVAgentDocsSyncResult result = await dvSyncAgentDocs(
        root: root.path,
        projectName: 'probe',
      );

      expect(result.created, isNotEmpty);
      expect(File(p.join(root.path, 'AGENTS.md')).existsSync(), isTrue);
      expect(result.version, isNotEmpty);
    });

    test('a project that already has the block is left alone', () async {
      await dvSyncAgentDocs(root: root.path, projectName: 'probe');
      final String before =
          File(p.join(root.path, 'AGENTS.md')).readAsStringSync();

      final DVAgentDocsSyncResult again =
          await dvSyncAgentDocs(root: root.path, projectName: 'probe');

      expect(again.updated, isEmpty);
      expect(again.created, isEmpty);
      expect(File(p.join(root.path, 'AGENTS.md')).readAsStringSync(), before);
    });

    test('it cannot fail the dev loop over documentation', () async {
      // A read-only project directory is not a reason to refuse to start.
      final Directory locked = Directory.systemTemp.createTempSync('dartvel_ro_');
      addTearDown(() {
        if (locked.existsSync()) locked.deleteSync(recursive: true);
      });
      Process.runSync('chmod', <String>['555', locked.path]);

      final DVAgentDocsSyncResult result =
          await dvSyncAgentDocs(root: locked.path, projectName: 'probe');

      Process.runSync('chmod', <String>['755', locked.path]);
      expect(result.failed, isNotEmpty);
    });
  });
}