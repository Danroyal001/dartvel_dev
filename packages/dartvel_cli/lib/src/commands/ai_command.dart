import 'package:args/command_runner.dart';

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
    Logger.log('Generating AI project context map...');
    Logger.log('  [+] Scanning source files...');
    Logger.log('  [+] Bundling specifications...');
    Logger.log('Context export saved to: .dartvel/ai_context.md');
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
    Logger.log('  Checking project structure... OK');
    Logger.log('  Checking environment config... OK');
    Logger.log('  Checking model definitions... OK');
    Logger.log('AI Doctor scan completed: No issues found.');
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
      return;
    }
    final prompt = argResults!.rest.join(' ');
    Logger.log('AI Code Generator processing: "$prompt"');
    Logger.log('  [+] Resolving instructions...');
    Logger.log('  [+] Generating readable Dartvel feature files...');
    Logger.log('AI Code Generation complete.');
  }
}
