import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../templates/project_templates.dart';
import '../utils/logger.dart';

class InitCommand extends Command<void> {
  @override
  final String name = 'create';

  @override
  String get description =>
      'Initialize a new Dartvel project with best practices.${aliases.isEmpty ? '' : ' (Aliases: ${aliases.join(', ')})'}';

  @override
  final List<String> aliases = ['init', 'new'];
  InitCommand() {
    argParser
      ..addFlag('web', defaultsTo: true, help: 'Include web platform')
      ..addFlag('mobile', defaultsTo: true, help: 'Include mobile platforms')
      ..addFlag('desktop', defaultsTo: false, help: 'Include desktop platforms')
      ..addFlag('ssr', defaultsTo: false, help: 'Enable SSR/SSG features')
      ..addOption('name', abbr: 'n', help: 'Project name')
      ..addOption('org',
          abbr: 'o', defaultsTo: 'com.example', help: 'Organization domain');
  }

  @override
  Future<void> run() async {
    var root = Directory.current.path;
    String? projectName;
    String? targetDir;

    // Check for positional argument
    if (argResults!.rest.isNotEmpty) {
      targetDir = argResults!.rest.first;
    } else {
      // Prompt user if no argument provided
      stdout.write('Project name (leave blank for current directory): ');
      final input = stdin.readLineSync()?.trim();
      if (input != null && input.isNotEmpty) {
        targetDir = input;
      }
    }

    // Handle target directory
    if (targetDir != null && targetDir != '.') {
      if (p.isAbsolute(targetDir)) {
        root = targetDir;
      } else {
        root = p.join(root, targetDir);
      }

      final dir = Directory(root);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
        Logger.log('Created project directory: $targetDir');
      }
    } else {
      Logger.log('Initializing in current directory: $root');
    }

    projectName ??= argResults?['name'] as String? ?? p.basename(root);
    final org = argResults?['org'] as String;
    final web = argResults?['web'] as bool;
    final mobile = argResults?['mobile'] as bool;
    final desktop = argResults?['desktop'] as bool;
    // SSR flag is currently unused but reserved for future use
    // final ssr = argResults?['ssr'] as bool? ?? false;

    Logger.log('🚀 Initializing Dartvel project: $projectName in $root');

    // Run flutter create to generate platform scaffolding
    Logger.log('📦 Running: flutter create .');
    final createArgs = ['create', '.', '--project-name', projectName];
    if (web) createArgs.add('--platforms=web');
    if (mobile) createArgs.add('--platforms=android,ios');
    if (desktop) createArgs.add('--platforms=linux,macos,windows');
    if (org != 'com.example') {
      createArgs.addAll(['--org', org]);
    }

    // Ensure directory exists before running flutter create
    if (!Directory(root).existsSync()) {
      Directory(root).createSync(recursive: true);
    }

    final createProc = await Process.run('flutter', createArgs,
        workingDirectory: root, runInShell: true);

    if (createProc.exitCode != 0) {
      Logger.log('⚠️  Warning: flutter create failed');
      Logger.log(createProc.stderr.toString());
      // Continue anyway as we might be able to recover or the user might fix it
    } else {
      Logger.log('✅ Flutter project scaffolded');
    }

    // Create pubspec.yaml (will overwrite the one from flutter create)
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      Logger.log('ℹ️  Overwriting pubspec.yaml with Dartvel configuration...');
    }

    pubspecFile.writeAsStringSync(ProjectTemplates.pubspecTemplate(
      name: projectName,
      org: org,
      web: web,
      mobile: mobile,
      desktop: desktop,
    ));

    // Create directory structure
    final directories = [
      'lib/pages',
      'lib/backend/functions',
      'assets',
      '.dartvel',
    ];

    for (final dir in directories) {
      Directory(p.join(root, dir)).createSync(recursive: true);
    }

    // Create .env with examples
    File(p.join(root, '.env')).writeAsStringSync(ProjectTemplates.envTemplate);
    File(p.join(root, '.env.example'))
        .writeAsStringSync(ProjectTemplates.envExampleTemplate);

    // Create example page
    File(p.join(root, 'lib/pages/index.page.dart'))
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

    // Create .gitignore
    File(p.join(root, '.gitignore'))
        .writeAsStringSync(ProjectTemplates.gitignoreTemplate);

    // Create analysis_options.yaml
    File(p.join(root, 'analysis_options.yaml'))
        .writeAsStringSync(ProjectTemplates.analysisOptionsTemplate);

    // Create README.md
    File(p.join(root, 'README.md'))
        .writeAsStringSync(ProjectTemplates.readmeTemplate(projectName));

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
