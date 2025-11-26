import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../templates/project_templates.dart';
import '../utils/logger.dart';

class NewCommand extends Command<void> {
  @override
  final String name = 'new';

  @override
  String get description =>
      'Create a new Dartvel project.${aliases.isEmpty ? '' : ' (Aliases: ${aliases.join(', ')})'}';

  @override
  final List<String> aliases = ['init', 'create'];

  NewCommand() {
    argParser
      ..addOption('template',
          help: 'Starter template to use', defaultsTo: 'app')
      ..addFlag('force',
          help: 'Overwrite existing directory if present', defaultsTo: false)
      ..addFlag('overwrite', help: 'Alias for --force', defaultsTo: false);
  }

  @override
  Future<void> run() async {
    final rest = argResults?.rest ?? [];
    if (rest.isEmpty) {
      Logger.log('Usage: dartvel new <project_name> [--template app]', isError: true);
      exit(2);
    }
    final projectName = rest.first;
    final targetDir = Directory(p.join(Directory.current.path, projectName));
    final force = (argResults?['force'] as bool) || (argResults?['overwrite'] as bool);
    
    if (targetDir.existsSync() && !force) {
      Logger.log('Directory "${targetDir.path}" already exists. Use --force to overwrite.', isError: true);
      exit(3);
    }
    if (targetDir.existsSync() && force) {
      Logger.log('Removing existing directory ${targetDir.path} (force).');
      await targetDir.delete(recursive: true);
    }
    targetDir.createSync(recursive: true);

    String sanitize(String input) =>
        input.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    final packageName = sanitize(projectName.toLowerCase());

    void writeFile(String relPath, String contents) {
      final file = File(p.join(targetDir.path, relPath));
      file.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    writeFile('pubspec.yaml', '${ProjectTemplates.pubspec(packageName).trim()}\n');
    writeFile('analysis_options.yaml', ProjectTemplates.analysisOptions);
    writeFile('README.md', ProjectTemplates.readme(projectName));
    writeFile('lib/pages/index.page.dart', ProjectTemplates.indexPage);
    writeFile('lib/pages/about.page.dart', ProjectTemplates.aboutPage);
    writeFile('lib/pages/_layout.page.dart', ProjectTemplates.layoutPage);
    writeFile('lib/backend/functions/hello.get.dart', ProjectTemplates.helloFunction);
    writeFile('lib/backend/functions/echo.post.dart', ProjectTemplates.echoFunction);
    writeFile('.gitignore', ProjectTemplates.gitignore);

    File(p.join(targetDir.path, '.env'))
        .writeAsStringSync('PUBLIC_API_HOST=http://localhost:3000\n');

    Logger.log('Created Dartvel project in ${targetDir.path}.');
    Logger.log('Run `cd $projectName && flutter pub get` to continue.');
  }
}
