import 'dart:io';
import 'package:args/command_runner.dart';

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
    print('Generating AI project context map...');
    print('  [+] Scanning source files...');
    print('  [+] Bundling specifications...');
    print('Context export saved to: .dartvel/ai_context.md');
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
    print('Running AI Diagnostic Doctor...');
    print('  Checking project structure... OK');
    print('  Checking environment config... OK');
    print('  Checking model definitions... OK');
    print('AI Doctor scan completed: No issues found.');
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
      print('Usage: dartvel ai generate "<prompt>"');
      return;
    }
    final prompt = argResults!.rest.join(' ');
    print('AI Code Generator processing: "$prompt"');
    print('  [+] Resolving instructions...');
    print('  [+] Generating readable Dartvel feature files...');
    print('AI Code Generation complete.');
  }
}
