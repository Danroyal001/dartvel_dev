/// Every coding agent a Dartvel project is set up for, generated from one
/// source.
///
/// A project created before this had no agent documentation at all, so
/// whichever tool you opened it in inferred the rules for itself and eleven
/// tools each wanted a differently named file. This is the answer Next.js
/// 16.3 gives, for Dartvel: one generated block, written to the file each tool
/// reads, refreshed by `dartvel dev` so it stays matched to the Dartvel
/// version that is actually installed.
///
/// Three decisions worth stating, because the alternatives are worse:
///
/// * **One source, many copies.** The copies are generated from
///   [dvAgentBlock] and refreshed from it, so they cannot drift apart by
///   construction. Hand-maintained copies drift; that is the problem this
///   replaces, not a thing to reproduce.
/// * **Tools that read `AGENTS.md` get no file of their own.** Codex, OpenCode,
///   Devin and ChatGPT read the project root's `AGENTS.md`. Four more copies
///   would be four more files that can disagree, so the canonical file says
///   which tools it serves and a test keeps that list honest.
/// * **A missing docs directory is reported, never invented.** The block points
///   at the documentation shipped with the installed Dartvel when it is there
///   and otherwise names `dartvel docs`, which builds the project's own
///   reference from its graph. It never prints a path that does not exist.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../commands/version_command.dart' show dartvelCliVersion;

/// What kind of file a target is, which decides how it is composed.
enum DVAgentDocKind {
  /// Markdown rules carrying the managed block.
  rules,

  /// A tool's own configuration format, which points at the rules file.
  config,
}

/// One file a project gets.
class DVAgentDocTarget {
  const DVAgentDocTarget({
    required this.path,
    required this.kind,
    required this.tools,
    this.header,
  });

  /// Where the file goes, relative to the project root.
  final String path;

  final DVAgentDocKind kind;

  /// The agents this file sets up. The canonical file's list is the record of
  /// which tools deliberately have no file of their own.
  final List<String> tools;

  /// Written above the block on creation, for formats that need it: Cursor's
  /// frontmatter, a provenance line. Never rewritten on refresh, because it
  /// belongs to the tool's format rather than to the rules.
  ///
  /// `{project}` is replaced with the project's package name, so the canonical
  /// file says which project it is talking about without a second read of
  /// pubspec.yaml.
  final String? header;
}

/// The start of the block Dartvel owns and rewrites.
///
/// Everything between the two markers is replaced on a refresh. Everything
/// outside them is the project's, and a refresh leaves it alone: a team that
/// wrote "do not merge without a review" above the block keeps it, and an
/// agent that reads the file still sees it.
const String dvAgentBlockBegin = '<!-- dartvel:begin agents -->';
const String dvAgentBlockEnd = '<!-- dartvel:end agents -->';

/// Every file a Dartvel project gets for its coding agents.
///
/// A function rather than a constant list so a caller cannot mutate it, and so
/// a test reads the same table the writer does.
List<DVAgentDocTarget> dvAgentDocTargets() => const <DVAgentDocTarget>[
      DVAgentDocTarget(
        path: 'AGENTS.md',
        kind: DVAgentDocKind.rules,
        tools: <String>[
          'Codex',
          'OpenCode',
          'Devin',
          'ChatGPT',
          'any agent that reads AGENTS.md',
        ],
        header: '# Dartvel\n\n'
            'These are the working rules for `{project}`. The block below is '
            'written by `dartvel dev` and matched to the Dartvel version you '
            'have installed; text outside it is yours and is never touched.\n',
      ),
      DVAgentDocTarget(
        path: 'CLAUDE.md',
        kind: DVAgentDocKind.rules,
        tools: <String>['Claude Code'],
        header: '# CLAUDE.md\n\n'
            'The same block as `AGENTS.md`, in the file Claude Code reads. Both '
            'are generated from one source, so neither can be wrong on its '
            'own.\n',
      ),
      DVAgentDocTarget(
        path: 'GEMINI.md',
        kind: DVAgentDocKind.rules,
        tools: <String>['Gemini CLI'],
      ),
      DVAgentDocTarget(
        path: 'AGENT.md',
        kind: DVAgentDocKind.rules,
        tools: <String>['agents that read AGENT.md'],
      ),
      DVAgentDocTarget(
        path: 'CONVENTIONS.md',
        kind: DVAgentDocKind.rules,
        tools: <String>['aider, and tools that read conventions'],
      ),
      DVAgentDocTarget(
        path: '.cursorrules',
        kind: DVAgentDocKind.rules,
        tools: <String>['Cursor (project rules)'],
      ),
      DVAgentDocTarget(
        path: '.cursor/rules/dartvel.mdc',
        kind: DVAgentDocKind.rules,
        tools: <String>['Cursor (rules directory)'],
        // Cursor applies a rule file from `.cursor/rules` only when its
        // frontmatter says so, and `.mdc` is not markdown without it.
        header: '---\n'
            'description: Dartvel working rules for this project\n'
            'alwaysApply: true\n'
            '---\n',
      ),
      DVAgentDocTarget(
        path: '.windsurfrules',
        kind: DVAgentDocKind.rules,
        tools: <String>['Windsurf'],
      ),
      DVAgentDocTarget(
        path: '.clinerules',
        kind: DVAgentDocKind.rules,
        tools: <String>['Cline'],
      ),
      DVAgentDocTarget(
        path: '.kiro/steering/dartvel.md',
        kind: DVAgentDocKind.rules,
        tools: <String>['Kiro'],
        header: '# Dartvel working rules\n',
      ),
      DVAgentDocTarget(
        path: '.github/copilot-instructions.md',
        kind: DVAgentDocKind.rules,
        tools: <String>['GitHub Copilot', 'ChatGPT in a GitHub repository'],
      ),
      DVAgentDocTarget(
        path: '.aider.conf.yml',
        kind: DVAgentDocKind.config,
        tools: <String>['aider'],
      ),
    ];

/// The generated block: the rules, the version they were written for, and
/// where that version's documentation is.
///
/// [docsPath] is the documentation shipped with the installed Dartvel, or null
/// when there is none beside it. Null prints `dartvel docs` instead of a path,
/// because a rules file pointing at a directory that does not exist is worse
/// than one naming a command that works.
String dvAgentBlock({
  required String version,
  required String rules,
  String? docsPath,
}) {
  final StringBuffer out = StringBuffer()
    ..writeln(dvAgentBlockBegin)
    ..writeln('<!-- Written by `dartvel dev`, matched to Dartvel $version.')
    ..writeln('     Edits inside this block are replaced; text outside it is kept. -->')
    ..writeln()
    ..writeln('## Dartvel $version')
    ..writeln()
    ..writeln(rules.trimRight())
    ..writeln()
    ..writeln('## Where to read more');
    if (docsPath != null) {
      out
        ..writeln()
        ..writeln('The documentation for this exact version ships with it, at:')
        ..writeln()
        ..writeln('    $docsPath')
        ..writeln()
        ..writeln('Read it before adding anything: it describes the API as '
            'this version has it, which is not always what the newest website '
            'says.');
    } else {
      out
        ..writeln()
        ..writeln('Run `dartvel docs` to build this project\'s own reference '
            'from its routes, data models, backend functions and jobs.');
    }
    out.writeln(dvAgentBlockEnd);
  return out.toString();
}

/// The content of a target's file: its format's header, then the block.
String dvRenderAgentDoc(
  DVAgentDocTarget target, {
  required String projectName,
  required String version,
  required String rules,
  String? docsPath,
}) {
  if (target.kind == DVAgentDocKind.config) {
    // YAML, not markdown. A `#` line in `.aider.conf.yml` is a comment, so the
    // rules cannot live here even as a comment block; aider is told to read
    // the file that holds them.
    return 'read:\n  - AGENTS.md\n  - CONVENTIONS.md\n';
  }
  final StringBuffer out = StringBuffer();
  final String? header = target.header;
  if (header != null) {
    out
      ..writeln(header.replaceAll('{project}', projectName).trimRight())
      ..writeln();
  }
  out.write(dvAgentBlock(version: version, rules: rules, docsPath: docsPath));
  return out.toString();
}

/// What happened, or would happen, to one file.
enum DVAgentDocAction { created, updated, unchanged }

/// One planned write.
class DVAgentDocWrite {
  const DVAgentDocWrite({
    required this.path,
    required this.filePath,
    required this.content,
    required this.action,
  });

  /// Where the file goes, relative to the project root: what a caller reports.
  final String path;

  /// The same file, absolute, so applying a plan never depends on the working
  /// directory it was applied from.
  final String filePath;

  final String content;
  final DVAgentDocAction action;

  bool get isWritten => action != DVAgentDocAction.unchanged;
}

/// Puts [block] into [existing], keeping everything outside the markers.
///
/// An existing file with no markers -- a team that had its own `CLAUDE.md`
/// before Dartvel was added -- keeps all of its text and gains the block below
/// it. Clobbering a file the project wrote is the one outcome this must never
/// have: an agent-config command that deletes somebody's rules is worse than
/// no command.
String dvMergeAgentBlock(String? existing, {required String block}) {
  final String current = existing ?? '';
  final int begin = current.indexOf(dvAgentBlockBegin);
  final int end = current.indexOf(dvAgentBlockEnd);
  if (begin < 0 || end < 0 || end < begin) {
    if (current.trim().isEmpty) return block;
    return '${current.trimRight()}\n\n$block';
  }
  final String before = current.substring(0, begin).trimRight();
  final String after = current.substring(end + dvAgentBlockEnd.length).trimLeft();
  final String merged = <String>[
    if (before.isNotEmpty) before,
    block.trimRight(),
    if (after.isNotEmpty) after,
  ].join('\n\n');
  // The same trailing newline a freshly written file has, or a refresh reads
  // as a change on every start and `dartvel dev` rewrites twelve files forever.
  return '$merged\n';
}

/// The files [root] should have, and what each one needs.
///
/// Pure with respect to the filesystem apart from reading, so a caller can ask
/// what would happen before anything is written -- which is what the create
/// and init flows do, and what a test asserts on.
List<DVAgentDocWrite> dvPlanAgentDocs({
  required String root,
  required String projectName,
  required String version,
  required String rules,
  String? docsPath,
}) {
  final List<DVAgentDocWrite> plan = <DVAgentDocWrite>[];
  for (final DVAgentDocTarget target in dvAgentDocTargets()) {
    final String filePath = p.join(root, target.path);
    final File file = File(filePath);
    final bool existed = file.existsSync();
    final String existing = existed ? file.readAsStringSync() : '';
    final String block = dvAgentBlock(
      version: version,
      rules: rules,
      docsPath: docsPath,
    );

    final String content;
    if (!existed) {
      content = dvRenderAgentDoc(
        target,
        projectName: projectName,
        version: version,
        rules: rules,
        docsPath: docsPath,
      );
    } else if (target.kind == DVAgentDocKind.config) {
      // A tool's own configuration is not ours to rewrite. `.aider.conf.yml`
      // also carries the developer's model, endpoint and API key settings,
      // and replacing the file to add two read paths would take those with it.
      // A file that already has ours is left as it is; one that has not gets
      // the two lines appended and keeps everything else.
      content = existing.contains('AGENTS.md')
          ? existing
          : '${existing.trimRight()}\nread:\n  - AGENTS.md\n  - CONVENTIONS.md\n';
    } else {
      content = dvMergeAgentBlock(existing, block: block);
    }

    plan.add(DVAgentDocWrite(
      path: target.path,
      filePath: filePath,
      content: content,
      action: !existed
          ? DVAgentDocAction.created
          : content == existing
              ? DVAgentDocAction.unchanged
              : DVAgentDocAction.updated,
    ));
  }
  return plan;
}

/// Writes the files in [plan] that need writing, and returns those writes.
///
/// The unchanged ones are dropped: a second `dartvel dev` opens no files and
/// changes no timestamps, which is what makes it safe to run on every start.
List<DVAgentDocWrite> dvApplyAgentDocs(List<DVAgentDocWrite> plan) {
  final List<DVAgentDocWrite> written = <DVAgentDocWrite>[];
  for (final DVAgentDocWrite write in plan) {
    if (!write.isWritten) continue;
    final File file = File(write.filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(write.content);
    written.add(write);
  }
  return written;
}

/// The documentation directory shipped with the installed Dartvel CLI, or
/// null.
///
/// Resolved through the package the CLI itself came from, so a project using a
/// published Dartvel is pointed at the documentation that version published
/// rather than at the repository's current one. Null when the CLI runs from a
/// directory where the documentation is not beside it, which is the normal case
/// for a checkout of this repository -- its own AGENTS.md is the source there.
Future<String?> dvBundledDocsPath() async {
  try {
    final Uri? uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_impl.dart'),
    );
    if (uri == null || !uri.isScheme('file')) return null;
    final String docs = p.join(p.dirname(p.dirname(uri.toFilePath())), 'docs');
    return Directory(docs).existsSync() ? docs : null;
  } catch (_) {
    return null;
  }
}

/// The rules shipped with the installed Dartvel, from
/// `docs/agents/rules.md` beside the CLI.
Future<String?> dvBundledAgentRules() async {
  final String? docs = await dvBundledDocsPath();
  if (docs == null) return null;
  final File file = File(p.join(docs, 'agents', 'rules.md'));
  if (!file.existsSync()) return null;
  final String body = file.readAsStringSync().trim();
  return body.isEmpty ? null : body;
}

/// The project's name, for the files that mention it.
String dvAgentProjectName(String root, String pubspecSource) {
  final RegExpMatch? match =
      RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspecSource);
  final String? name = match?.group(1);
  return name != null && name.isNotEmpty ? name : p.basename(root);
}

/// What a sync did.
class DVAgentDocsSyncResult {
  const DVAgentDocsSyncResult({
    required this.version,
    this.created = const <String>[],
    this.updated = const <String>[],
    this.failed = const <String>[],
    this.rulesFrom = 'dartvel',
  });

  final String version;
  final List<String> created;
  final List<String> updated;

  /// Files that could not be written. Reported, never thrown: a development
  /// loop must not stop because a directory is read-only.
  final List<String> failed;

  /// Where the rules came from: the installed package, or the copy this CLI
  /// carries. Said out loud, because a project pointed at another version's
  /// rules without being told is how the drift the roadmap describes starts.
  final String rulesFrom;

  bool get isQuiet => created.isEmpty && updated.isEmpty && failed.isEmpty;

  List<String> get allWritten => <String>[...created, ...updated];
}

/// Sets up, or refreshes, every agent file in [root].
///
/// Called by `dartvel create`, by `dartvel init` on a project being adopted,
/// and by `dartvel dev` on every start -- the third is what keeps a project's
/// rules matched to the version it is on without anyone running a command.
///
/// Returns what it did rather than throwing: a read-only checkout, a
/// permission problem, a filesystem that does not answer. None of those is a
/// reason to refuse to start a development server.
Future<DVAgentDocsSyncResult> dvSyncAgentDocs({
  required String root,
  String? projectName,
  String version = dartvelCliVersion,
}) async {
  final String? bundled = await dvBundledAgentRules();
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  final String name = projectName ??
      dvAgentProjectName(root, pubspec.existsSync() ? pubspec.readAsStringSync() : '');

  // The rules this CLI carries are the floor. The installed package's own file
  // is preferred when it has one, because a project on a newer Dartvel should
  // be told the newer rules and not this binary's memory of them.
  final String rules = bundled ?? _fallbackRules;
  final String? docsPath = await dvBundledDocsPath();

  final List<DVAgentDocWrite> plan = dvPlanAgentDocs(
    root: root,
    projectName: name,
    version: version,
    rules: rules,
    docsPath: docsPath,
  );

  final List<String> created = <String>[];
  final List<String> updated = <String>[];
  final List<String> failed = <String>[];
  for (final DVAgentDocWrite write in plan) {
    if (!write.isWritten) continue;
    try {
      final File file = File(p.join(root, write.path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(write.content);
      (write.action == DVAgentDocAction.created ? created : updated).add(write.path);
    } catch (_) {
      failed.add(write.path);
    }
  }

  return DVAgentDocsSyncResult(
    version: version,
    created: created,
    updated: updated,
    failed: failed,
    rulesFrom: bundled == null
        ? 'the dartvel_cli that is running'
        : 'the installed dartvel_cli',
  );
}

/// The rules this CLI carries when the installed package has no rules file.
///
/// Ten lines, not the full body: enough that an agent reading a project with no
/// documentation still gets the load-bearing shape rules, and a pointer to
/// `dartvel docs` for the rest. A copy of the whole rule set is what this
/// whole feature exists to stop.
const String _fallbackRules = '''
- Application code imports the generated `dartvel_client/dartvel_client.dart`
  barrel, never a generated sibling file directly.
- Data models are the only way data is written: `Order(...).save()`,
  `order.delete()`, `Order.find(...)`. Never a record insert, a table name, or
  a SQL string.
- Routes are typed: the generated `DVRoutes` member, never a path written out
  as a string.
- `@DVModel` inputs are private and start with `_`; application code uses the
  generated public API.
- One generator: `dartvel routes`, which `dartvel build` and `dartvel dev` run
  for you. No `build_runner`, no `build.yaml`.
- Native integrations are FFI/ffigen or JNI/jnigen. No `MethodChannel`.
- Application-facing Dart uses primary constructors and dot shorthands.
''';