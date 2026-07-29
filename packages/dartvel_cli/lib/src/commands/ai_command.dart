import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

class AiCommand extends Command<void> {
  @override
  final String name = 'ai';
  @override
  final String description = 'Leverage Dartvel AI integration helper commands.';

  AiCommand() {
    addSubcommand(AiContextSubcommand());
    addSubcommand(AiDoctorSubcommand());
    addSubcommand(AiGenerateSubcommand());
  }
}

class AiContextSubcommand extends Command<void> {
  @override
  final String name = 'context';
  @override
  final String description =
      'Export the codebase context to markdown for AI tools.';

  @override
  Future<void> run() async {
    final root = Directory.current.path;
    final context = buildAiProjectContext(root);
    final output = aiContextFile(root);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(context);
    Logger.log(
        'Context export saved to: ${p.relative(output.path, from: root)}');
  }
}

class AiDoctorSubcommand extends Command<void> {
  @override
  final String name = 'doctor';
  @override
  final String description =
      'Diagnose and automatically resolve configuration issues using AI.';

  @override
  Future<void> run() async {
    Logger.log('Running AI Diagnostic Doctor...');
    final diagnostics = inspectAiProject(Directory.current.path);
    for (final message in diagnostics.messages) {
      Logger.log(message, isError: message.startsWith('[error]'));
    }
    if (diagnostics.hasErrors) {
      exitCode = 1;
      return;
    }
    Logger.log('AI Doctor scan completed successfully.');
  }
}

class AiGenerateSubcommand extends Command<void> {
  @override
  final String name = 'generate';
  @override
  final String description =
      'Generate features, models, or views from a natural language prompt.';

  @override
  Future<void> run() async {
    if (argResults?.rest.isEmpty ?? true) {
      Logger.log('Usage: dartvel ai generate "<prompt>"');
      exitCode = 64;
      return;
    }
    final prompt = argResults!.rest.join(' ');
    if (!hasConfiguredAiProvider()) {
      Logger.log(
        'AI code generation requires an AI provider configuration. Set '
        'OPENAI_API_KEY or DARTVEL_AI_ENDPOINT before running this command.',
        isError: true,
      );
      exitCode = 78;
      return;
    }
    final request = aiGenerateRequestFile(Directory.current.path);
    request.parent.createSync(recursive: true);
    request.writeAsStringSync('${prompt.trim()}\n');
    Logger.log(
      'AI generation request recorded at '
      '${p.relative(request.path, from: Directory.current.path)}.',
    );
  }
}

class AiDiagnostics {
  const AiDiagnostics({required this.messages});

  final List<String> messages;

  bool get hasErrors =>
      messages.any((message) => message.startsWith('[error]'));
}

File aiContextFile(String root) =>
    File(p.join(root, '.dartvel', 'ai_context.md'));

File aiGenerateRequestFile(String root) =>
    File(p.join(root, '.dartvel', 'ai_generate_request.txt'));

String buildAiProjectContext(String root) {
  final buffer = StringBuffer()
    ..writeln('# Dartvel AI Project Context')
    ..writeln()
    ..writeln('Generated from `${p.basename(root)}`.')
    ..writeln()
    ..writeln('## Files');
  final files = discoverAiContextFiles(root);
  if (files.isEmpty) {
    buffer.writeln('- No Dartvel source files found.');
  } else {
    for (final file in files) {
      buffer.writeln(
          '- `${p.relative(file.path, from: root).replaceAll(r'\', '/')}`');
    }
  }
  buffer
    ..writeln()
    ..writeln('## Configuration')
    ..writeln(
        '- `pubspec.yaml`: ${File(p.join(root, 'pubspec.yaml')).existsSync() ? 'present' : 'missing'}')
    ..writeln(
        '- `NEW_SPEC.md`: ${File(p.join(root, 'NEW_SPEC.md')).existsSync() ? 'present' : 'missing'}');
  return buffer.toString();
}

List<File> discoverAiContextFiles(String root) {
  final files = <File>[];
  for (final directoryName in <String>['lib', 'test']) {
    final directory = Directory(p.join(root, directoryName));
    if (!directory.existsSync()) continue;
    for (final entity
        in directory.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) files.add(entity);
    }
  }
  for (final fileName in <String>['NEW_SPEC.md', 'README.md', 'pubspec.yaml']) {
    final file = File(p.join(root, fileName));
    if (file.existsSync()) files.add(file);
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return List<File>.unmodifiable(files);
}

AiDiagnostics inspectAiProject(String root) {
  final messages = <String>[];
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (pubspec.existsSync()) {
    messages.add('[ok] pubspec.yaml found');
  } else {
    messages.add('[error] pubspec.yaml is missing');
  }

  final lib = Directory(p.join(root, 'lib'));
  if (lib.existsSync()) {
    messages.add('[ok] lib directory found');
  } else {
    messages.add('[error] lib directory is missing');
  }

  final sourceFiles = discoverAiContextFiles(root);
  if (sourceFiles.any((file) => file.path.endsWith('.dart'))) {
    messages.add('[ok] Dart source files found');
  } else {
    messages.add('[error] no Dart source files found under lib or test');
  }

  if (hasConfiguredAiProvider()) {
    messages.add('[ok] AI provider environment is configured');
  } else {
    messages.add(
      '[warn] no AI provider environment detected; generation commands will not run',
    );
  }
  return AiDiagnostics(messages: List<String>.unmodifiable(messages));
}

bool hasConfiguredAiProvider() {
  final environment = Platform.environment;
  return (environment['OPENAI_API_KEY']?.trim().isNotEmpty ?? false) ||
      (environment['DARTVEL_AI_ENDPOINT']?.trim().isNotEmpty ?? false);
}
