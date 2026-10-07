import 'dart:io';
import 'dart:isolate';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../commands/version_command.dart' show dartvelCliVersion;
import '../agents/agent_docs.dart';
import '../agents/architecture_docs.dart';
import '../templates/project_templates.dart';
import '../utils/logger.dart';
import 'adopt_command.dart' show dvAdoptFromTerminal;

/// Why `create` must not scaffold in [root], or null when it may.
///
/// `create` replaces `pubspec.yaml` with the Dartvel template. In an empty
/// directory that file is the one `flutter create` wrote a moment earlier, so
/// replacing it costs nothing. In a directory that already holds an
/// application it costs the team every dependency, version and setting they
/// had declared. `init` used to be an alias of this command, and it is the
/// word someone with an existing project reaches for; it is AdoptCommand now.
///
/// The marker is the `dartvel:` key at the top level: the template writes it
/// and nothing else does, so a pubspec carrying one came from here and may be
/// written again. A pubspec without one belongs to somebody else.
String? dvForeignProjectRefusal(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;

  final String source = pubspec.readAsStringSync();
  // At the start of a line and not inside a comment: a commented-out example
  // is something a reader pasted while reading the documentation, and their
  // file is still theirs.
  if (RegExp(r'^dartvel:', multiLine: true).hasMatch(source)) return null;

  return 'DV-ADOPT-005: ${pubspec.path} was not written by Dartvel, and '
      '`dartvel create` would replace it — every dependency and setting in '
      'it. Refusing.\n'
      '  create makes a project that does not exist yet; run it in an empty '
      'directory, or pass a new directory name.\n'
      '  To add Dartvel to this project instead, run `dartvel init`: it adds '
      'the dependency and a `dartvel:` key, shows the change first, and '
      'writes nothing else.';
}

/// Where the Dartvel packages sit when this CLI runs from the monorepo, or
/// null when it runs from an installed package.
///
/// Both `create` and `init` write path dependencies in that case, so a
/// project made or adopted from a checkout resolves against that checkout.
Future<String?> dvLocalPackagesDir() async {
  try {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_impl.dart'),
    );
    if (uri == null || !uri.isScheme('file')) return null;
    final packageDir = Directory(p.dirname(p.dirname(uri.toFilePath())));
    final packagesDir = packageDir.parent;
    final required = [
      'dartvel_core',
      'dartvel_shelf',
      'dartvel_flutter',
      'dartvel_cli',
    ];
    final hasAll = required.every(
      (name) =>
          File(p.join(packagesDir.path, name, 'pubspec.yaml')).existsSync(),
    );
    return hasAll ? packagesDir.path : null;
  } catch (_) {
    return null;
  }
}

/// Where `dartvel create` will scaffold, and the package name it will use.
class DVCreateTarget {
  const DVCreateTarget(this.root, this.projectName, {required this.createsFolder});

  final String root;
  final String projectName;

  /// False when the project goes into the folder the command was run in.
  final bool createsFolder;
}

final RegExp _packageName = RegExp(r'^[a-z][a-z0-9_]*$');

/// Resolves the folder and package name the way `flutter create` does.
///
/// A [folder] on the command line is created (`.` is the current folder) and
/// names the package unless [projectName] overrides it. With no folder, an
/// interactive reader is asked whether the current folder is the one: Enter
/// or "y" uses it, "n" asks for a folder name, and anything else typed is the
/// folder to create. With nobody to ask, the current folder is used.
DVCreateTarget dvResolveCreateTarget({
  required String cwd,
  String? folder,
  String? projectName,
  bool interactive = false,
  String? Function(String question)? ask,
}) {
  if (folder == null && interactive && ask != null) {
    final String answer = (ask(
              'Create the project in the current folder '
              '(${p.basename(cwd)})? [Y/n, or type a folder name] ',
            ) ??
            '')
        .trim();
    final String lower = answer.toLowerCase();
    if (lower == 'n' || lower == 'no') {
      String name = '';
      while (name.isEmpty) {
        name = (ask('Folder name: ') ?? '').trim();
      }
      folder = name;
    } else if (answer.isNotEmpty && lower != 'y' && lower != 'yes') {
      folder = answer;
    }
  }

  final bool here = folder == null || folder == '.';
  final String root = here ? cwd : p.normalize(p.join(cwd, folder));
  final String name = projectName ?? p.basename(root);
  if (!_packageName.hasMatch(name)) {
    final String suggestion = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'^[^a-z]+'), '');
    throw UsageException(
      '"$name" is not a valid Dart package name: use lowercase letters, '
      'digits and underscores, starting with a letter. Name the folder '
      '${suggestion.isEmpty ? 'that way' : '"$suggestion"'}, or keep the '
      'folder and pass --project-name ${suggestion.isEmpty ? '<name>' : suggestion}.',
      'dartvel create [<folder>] [--project-name <name>]',
    );
  }
  return DVCreateTarget(root, name, createsFolder: !here);
}

class InitCommand extends Command<void> {
  @override
  final String name = 'create';

  @override
  String get description =>
      'Create a Dartvel project, or add Dartvel to the project already in the folder (the same as dartvel init).${aliases.isEmpty ? '' : ' (Aliases: ${aliases.join(', ')})'}';

  // Not `init`: that initializes Dartvel inside a project that already
  // exists, and is AdoptCommand. As an alias of this command it replaced
  // the adopting project's pubspec with the scaffold template.
  @override
  final List<String> aliases = ['new'];

  @override
  String get invocation => 'dartvel create [<folder>] [--project-name <name>]';
  InitCommand() {
    argParser
      ..addFlag('web', defaultsTo: true, help: 'Include web platform')
      ..addFlag('mobile', defaultsTo: true, help: 'Include mobile platforms')
      ..addFlag('desktop', defaultsTo: true, help: 'Include desktop platforms')
      ..addFlag('ssr', defaultsTo: false, help: 'Enable SSR/SSG features')
      ..addOption('project-name',
          help: 'The package name, when it should differ from the folder\'s. '
              'Lowercase with underscores, as `flutter create` requires.')
      ..addOption('org',
          abbr: 'o', defaultsTo: 'com.example', help: 'Organization domain')
      // The same two as `dartvel init`: in a project Dartvel did not make,
      // create adopts it exactly as init does.
      ..addFlag('dry-run',
          negatable: false,
          help: 'In an existing project: print the adoption plan; write nothing.')
      ..addFlag('yes',
          abbr: 'y',
          negatable: false,
          help: 'In an existing project: apply the adoption plan without asking.');
  }

  @override
  Future<void> run() async {
    // `create` and `init` are one command: a project that is already there
    // -- here, or in the folder named -- is adopted, the plan first and
    // nothing of its own overwritten, never scaffolded over. Before naming
    // anything: an existing project already has its name.
    final String existingRoot = argResults!.rest.isEmpty
        ? Directory.current.path
        : p.absolute(argResults!.rest.first);
    if (dvForeignProjectRefusal(existingRoot) != null) {
      final int code = await dvAdoptFromTerminal(
        existingRoot,
        dryRun: argResults!['dry-run'] as bool,
        assumeYes: argResults!['yes'] as bool,
      );
      if (code != 0) exitCode = code;
      return;
    }
    final DVCreateTarget target = dvResolveCreateTarget(
      cwd: Directory.current.path,
      folder: argResults!.rest.isEmpty ? null : argResults!.rest.first,
      projectName: argResults!['project-name'] as String?,
      interactive: stdin.hasTerminal,
      ask: (String question) {
        stdout.write(question);
        return stdin.readLineSync();
      },
    );
    final String root = target.root;
    final String projectName = target.projectName;

    if (target.createsFolder) {
      final dir = Directory(root);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        Logger.log('Created project directory: ${p.relative(root)}');
      }
    } else {
      Logger.log('Initializing in current directory: $root');
    }

    final org = argResults?['org'] as String;
    final web = argResults?['web'] as bool;
    final mobile = argResults?['mobile'] as bool;
    final desktop = argResults?['desktop'] as bool;
    // SSR flag is currently unused but reserved for future use
    // final ssr = argResults?['ssr'] as bool? ?? false;

    // Before anything writes. `flutter create` runs next and produces a
    // pubspec of its own, so after that point there is no way to tell whose
    // file is on disk.


    Logger.log('🚀 Initializing Dartvel project: $projectName in $root');

    // Ensure directory exists
    if (!Directory(root).existsSync()) {
      Directory(root).createSync(recursive: true);
    }

    // Create pubspec.yaml
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      Logger.log('ℹ️  Overwriting pubspec.yaml with Dartvel configuration...');
    }

    final localPackagesDir = await dvLocalPackagesDir();
    pubspecFile.writeAsStringSync(ProjectTemplates.pubspecTemplate(
      name: projectName,
      org: org,
      web: web,
      mobile: mobile,
      desktop: desktop,
      localPackagesDir: localPackagesDir,
    ));

    // Create directory structure
    final directories = [
      'lib/pages',
      'lib/models',
      'lib/backend/functions',
      'lib/components',
      'lib/styles',
      'lib/services',
      'assets',
      '.dartvel',
      'test',
    ];

    for (final dir in directories) {
      Directory(p.join(root, dir)).createSync(recursive: true);
    }

    // Create .env with examples
    File(p.join(root, '.env')).writeAsStringSync(ProjectTemplates.envTemplate);
    File(p.join(root, '.env.example'))
        .writeAsStringSync(ProjectTemplates.envExampleTemplate);

    // Create example page
    File(p.join(root, 'lib/pages/index.dart'))
        .writeAsStringSync(ProjectTemplates.indexPageTemplate);

    // Create loading and error states
    File(p.join(root, 'lib/pages/index.loading.dart')).writeAsStringSync(
        ProjectTemplates.loadingTemplate('IndexPageLoading'));
    File(p.join(root, 'lib/pages/index.error.dart'))
        .writeAsStringSync(ProjectTemplates.errorTemplate('IndexPageError'));

    // Create example backend function
    File(p.join(root, 'lib/backend/functions/health.get.dart'))
        .writeAsStringSync(ProjectTemplates.healthFunctionTemplate);

    // Create POST example
    File(p.join(root, 'lib/backend/functions/contact.dart'))
        .writeAsStringSync(ProjectTemplates.contactFormTemplate);

    // Create main.dart
    File(p.join(root, 'lib/main.dart'))
        .writeAsStringSync(ProjectTemplates.mainTemplate);

    // Replace Flutter's stock test, which refers to the removed MyApp class.
    File(p.join(root, 'test/widget_test.dart'))
        .writeAsStringSync(ProjectTemplates.widgetTestTemplate(projectName));

    // Create .gitignore
    File(p.join(root, '.gitignore'))
        .writeAsStringSync(ProjectTemplates.gitignoreTemplate);

    // Create analysis_options.yaml
    File(p.join(root, 'analysis_options.yaml'))
        .writeAsStringSync(ProjectTemplates.analysisOptionsTemplate);

    // Create README.md
    File(p.join(root, 'README.md'))
        .writeAsStringSync(ProjectTemplates.readmeTemplate(projectName));

    // Set up every coding agent the project is going to be opened in, from one
    // source. A project with no rules file is read by whichever agent happens
    // to be opened, and eleven tools each want a differently named file; the
    // generated block is matched to this Dartvel's version and refreshed by
    // `dartvel dev` from then on.
    final agentDocs =
        await dvSyncAgentDocs(root: root, projectName: projectName);
    if (agentDocs.created.isNotEmpty) {
      Logger.log('🤖 Agent rules set up: ${agentDocs.created.join(', ')}');
    }
    if (agentDocs.failed.isNotEmpty) {
      Logger.log(
          '⚠️  Could not write ${agentDocs.failed.join(', ')} — the project\'s own text was left alone.');
    }

    // Opinionated architecture docs: initialisation, data, HTTP, UI, naming,
    // setup, Git, process, and Dartvel-specific (models, backend functions,
    // Studio, modules). Refreshed by `dartvel dev` like the agent rules.
    final archDocs = await dvSyncArchitectureDocs(
      root: root,
      version: dartvelCliVersion,
    );
    if (archDocs.created.isNotEmpty || archDocs.updated.isNotEmpty) {
      Logger.log(
          '📘 Architecture docs: ${archDocs.created.isNotEmpty ? 'created' : 'updated'} '
          '${[...archDocs.created, ...archDocs.updated].join(', ')}');
    }
    if (archDocs.failed.isNotEmpty) {
      Logger.log(
          '⚠️  Could not write architecture docs (${archDocs.failed.join(', ')}).');
    }

    Logger.log('✅ Project structure created');
    Logger.log('📦 Running: flutter pub get');

    // Run pub get
    final proc = await Process.run('flutter', ['pub', 'get'],
        workingDirectory: root, runInShell: true);
    if (proc.exitCode != 0) {
      Logger.log('⚠️  Warning: flutter pub get failed');
      Logger.log(proc.stderr.toString());
    }

    Logger.log('');
    Logger.log('✅ Project initialized successfully!');
    Logger.log('');
    Logger.log('Next steps:');
    Logger.log('  1. Review .env and add your configuration');
    Logger.log('  2. Run: dartvel dev');
    Logger.log('  3. Open http://localhost:3000 in your browser');
    Logger.log('');
    Logger.log('📚 Docs: https://dartvel.dev');
  }
}
