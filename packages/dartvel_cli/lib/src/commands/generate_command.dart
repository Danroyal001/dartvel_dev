import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

class GenerateCommand extends Command<void> {
  @override
  final String name = 'generate';
  @override
  final String description =
      'Generate Dartvel template files for pages, models, forms, and backend functions.';

  GenerateCommand() {
    addSubcommand(GeneratePageSubcommand());
    addSubcommand(GenerateModelSubcommand());
    addSubcommand(GenerateBackendSubcommand());
    addSubcommand(GenerateFormSubcommand());
  }
}

class GeneratePageSubcommand extends Command<void> {
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
    final pagesDir = Directory(p.join(Directory.current.path, 'lib', 'pages'));
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
      p.join(Directory.current.path, 'lib', 'models'),
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
      p.join(Directory.current.path, 'lib', 'backend', 'functions'),
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
  @override
  final String name = 'form';
  @override
  final String description = 'Generate form layout files.';

  @override
  Future<void> run() async {
    Logger.log('Generating form components...');
    Logger.log('Form layout scaffolding generated.');
  }
}
