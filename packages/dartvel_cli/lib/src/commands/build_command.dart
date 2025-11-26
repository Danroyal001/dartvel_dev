import 'dart:io';
import 'package:args/command_runner.dart';
import '../generators/routes_generator.dart';
import '../utils/logger.dart';

class BuildCommand extends Command<void> {
  @override
  final String name = 'build';

  @override
  final String description = 'Generate production-ready artifacts.';

  @override
  Future<void> run() async {
    await generate(validateProd: true);
    
    Logger.log('Building Flutter web app...');
    final buildResult = await Process.run('flutter', ['build', 'web', '--release']);
    if (buildResult.exitCode != 0) {
      Logger.error('Flutter build failed: ${buildResult.stderr}');
      exit(buildResult.exitCode);
    }
    
    Logger.log('Generating SSG data...');
    final ssgResult = await Process.run('dart', ['run', '.dartvel/ssg_builder.dart']);
    if (ssgResult.exitCode != 0) {
      Logger.error('SSG generation failed: ${ssgResult.stderr}');
      // Don't fail the whole build, just warn? Or fail?
      // SSG failure might mean some pages are broken. Let's fail.
      exit(ssgResult.exitCode);
    }
    
    Logger.log('Generated production-ready artifacts.');
  }
}
