import 'dart:io';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../build/render_backends.dart';
import '../generators/generate_check.dart';
import '../utils/logger.dart';

class GenerateCommand extends Command<void> {
  @override
  final String name = 'generate';
  @override
  final String description =
      'Generate Dartvel template files for pages, models, forms, and backend '
      'functions. With --check, fail when generated output is stale.';

  /// [root] is the project; null reads the working directory when the command
  /// runs. A test passes its own, because that directory is one value shared
  /// by every suite in the process.
  GenerateCommand({String? root}) {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help: 'Regenerate into a scratch location and compare, twice. Exits '
            'non-zero and prints the paths when the project\'s generated '
            'output is stale (DV-GEN-001) or generation is not deterministic '
            '(DV-GEN-002). Writes nothing into the project.',
      )
      ..addOption(
        'render',
        help: 'The rendering backends the checked output was generated for '
            '(gui, terminal, or both), as `dartvel routes --render`.',
      );
    addSubcommand(GeneratePageSubcommand(root: root));
    addSubcommand(GenerateModelSubcommand(root: root));
    addSubcommand(GenerateBackendSubcommand(root: root));
    addSubcommand(GenerateFormSubcommand(root: root));
  }
}

/// The Dartvel command runner.
///
/// `dartvel generate --check` is a flag on a command that also has
/// subcommands, and `args` refuses a command with subcommands that is run
/// without one before the command itself is reached. So it is dispatched
/// here instead.
class DartvelCommandRunner extends CommandRunner<void> {
  DartvelCommandRunner(super.executableName, super.description);

  @override
  Future<void> runCommand(ArgResults topLevelResults) async {
    final ArgResults? generate = topLevelResults.command;
    if (generate != null &&
        generate.name == 'generate' &&
        generate.command == null &&
        generate.flag('check')) {
      exitCode = await runGenerateCheck(
        Directory.current.path,
        renderBackends:
            parseRenderBackends(generate.option('render')),
      );
      return;
    }
    return super.runCommand(topLevelResults);
  }
}

/// Runs the check on [root], prints what it found, and returns the exit code.
Future<int> runGenerateCheck(
  String root, {
  Set<DVRenderBackend>? renderBackends,
}) async {
  final DVGenerateCheckResult result =
      await dvGenerateCheck(root, renderBackends: renderBackends);
  for (final String path in result.unstable) {
    stderr.writeln('DV-GEN-002: $path: generated output differs between two '
        'runs on the same input');
  }
  for (final String path in result.stale) {
    stderr.writeln('DV-GEN-001: $path: committed generated output is stale; '
        'run the generator');
  }
  if (result.ok) {
    Logger.log('Generated output is up to date.');
    return 0;
  }
  return 1;
}

class GeneratePageSubcommand extends Command<void> {
  GeneratePageSubcommand({this._root});

  final String? _root;

  @override
  final String name = 'page';
  @override
  final String description = 'Generate a new page functional widget.';

  @override
  Future<void> run() async {
    if (argResults?.rest.isEmpty ?? true) {
      Logger.log('Usage: dartvel generate page <page_name>');
      return;
    }
    final pageName = argResults!.rest.first;
    final pagesDir =
        Directory(p.join(_root ?? Directory.current.path, 'lib', 'pages'));
    if (!pagesDir.existsSync()) {
      pagesDir.createSync(recursive: true);
    }
    final file = File(p.join(pagesDir.path, '${pageName.toLowerCase()}.dart'));
    if (file.existsSync()) {
      Logger.log('Page file already exists: ${file.path}');
      return;
    }
    final capitalized = pageName[0].toUpperCase() + pageName.substring(1);
    file.writeAsStringSync('''import '../dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage()
@pragma('vm:entry-point')
Widget _${pageName.toLowerCase()}Page(BuildContext context) => DVBox(
      const DVText('$capitalized Page'),
      const DVModifier().align(Alignment.center),
    );
''');
    Logger.log('Generated page: ${file.path}');
  }
}

class GenerateModelSubcommand extends Command<void> {
  GenerateModelSubcommand({this._root});

  final String? _root;

  @override
  final String name = 'model';
  @override
  final String description = 'Generate a new data model class.';

  @override
  Future<void> run() async {
    if (argResults?.rest.isEmpty ?? true) {
      Logger.log('Usage: dartvel generate model <model_name>');
      return;
    }
    final modelName = argResults!.rest.first;
    final modelsDir = Directory(
      p.join(_root ?? Directory.current.path, 'lib', 'models'),
    );
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }
    final file = File(
      p.join(modelsDir.path, '${modelName.toLowerCase()}.dart'),
    );
    if (file.existsSync()) {
      Logger.log('Model file already exists: ${file.path}');
      return;
    }
    final capitalized = modelName[0].toUpperCase() + modelName.substring(1);
    file.writeAsStringSync('''import 'package:dartvel_core/dartvel.dart';

@DVModel()
@pragma('vm:entry-point')
class _$capitalized {
  final String id;
  final String name;

  const _$capitalized({required this.id, required this.name});
}
''');
    Logger.log('Generated model: ${file.path}');
  }
}

class GenerateBackendSubcommand extends Command<void> {
  GenerateBackendSubcommand({this._root});

  final String? _root;

  @override
  final String name = 'backend-function';
  @override
  final String description = 'Generate a new backend function.';

  @override
  Future<void> run() async {
    if (argResults?.rest.isEmpty ?? true) {
      Logger.log('Usage: dartvel generate backend-function <function_name>');
      return;
    }
    final funcName = argResults!.rest.first;
    final backendDir = Directory(
      p.join(_root ?? Directory.current.path, 'lib', 'backend', 'functions'),
    );
    if (!backendDir.existsSync()) {
      backendDir.createSync(recursive: true);
    }
    final file = File(
      p.join(backendDir.path, '${funcName.toLowerCase()}.dart'),
    );
    if (file.existsSync()) {
      Logger.log('Backend function file already exists: ${file.path}');
      return;
    }
    final capitalized = funcName[0].toUpperCase() + funcName.substring(1);
    file.writeAsStringSync('''import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
@pragma('vm:entry-point')
Future<String> _get$capitalized(String input) async => 'Echo: \$input';
''');
    Logger.log('Generated backend function: ${file.path}');
  }
}

class GenerateFormSubcommand extends Command<void> {
  GenerateFormSubcommand({this._root});

  final String? _root;

  @override
  final String name = 'form';
  @override
  final String description = 'Generate a form functional widget for a model.';

  @override
  Future<void> run() async {
    if (argResults?.rest.isEmpty ?? true) {
      Logger.log('Usage: dartvel generate form <model_name>');
      exitCode = 64;
      return;
    }
    final modelName = argResults!.rest.first;
    final formsDir =
        Directory(p.join(_root ?? Directory.current.path, 'lib', 'forms'));
    if (!formsDir.existsSync()) {
      formsDir.createSync(recursive: true);
    }
    final file =
        File(p.join(formsDir.path, '${modelName.toLowerCase()}_form.dart'));
    if (file.existsSync()) {
      Logger.log('Form file already exists: ${file.path}');
      return;
    }
    final capitalized = modelName[0].toUpperCase() + modelName.substring(1);
    final lower = modelName[0].toLowerCase() + modelName.substring(1);
    file.writeAsStringSync('''import '../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVFunctionalWidget()
@pragma('vm:entry-point')
Widget _${lower}Form(BuildContext context, $capitalized model) =>
    model.Form();
''');
    Logger.log('Generated form: ${file.path}');
  }
}
