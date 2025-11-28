import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';

class DoctorCommand extends Command<void> {
  @override
  final String name = 'doctor';

  @override
  final String description = 'Check your environment and project for common issues.';

  @override
  Future<void> run() async {
    Logger.log('�� Dartvel Doctor\n');

    var allGood = true;

    // 1. Check Dart SDK
    allGood = await _checkDartSDK() && allGood;

    // 2. Check Flutter SDK
    allGood = await _checkFlutterSDK() && allGood;

    // 3. Check Git
    allGood = await _checkGit() && allGood;

    // 4. If in a Dartvel project, check project-specific things
    final pubspec = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      Logger.log('\n📦 Project Check');
      await _checkProjectConfig();
    } else {
      Logger.log('\n📦 Not in a Dartvel project');
      Logger.log('ℹ️  Run this command in a project directory for additional checks');
    }

    Logger.log('');
    if (allGood) {
      Logger.log('✅ All system checks passed!');
    } else {
      Logger.log('⚠️  Some checks failed. See above for details.');
    }
  }

  Future<bool> _checkDartSDK() async {
    try {
      final result = await Process.run('dart', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = (result.stdout.toString() + result.stderr.toString()).split('\n').first.trim();
        Logger.log('✅ Dart SDK: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('❌ Dart SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkFlutterSDK() async {
    try {
      final result = await Process.run('flutter', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final version = lines.isNotEmpty ? lines.first.trim() : 'installed';
        Logger.log('✅ Flutter SDK: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('❌ Flutter SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkGit() async {
    try {
      final result = await Process.run('git', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        Logger.log('✅ Git: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('⚠️  Git: Not found (recommended for version control)');
    return true; // Not critical
  }

  Future<void> _checkProjectConfig() async {
    Logger.log('  ℹ️  Dartvel project checks not yet fully implemented');
    Logger.log('  ℹ️  Project detection and validation coming soon');
  }
}
