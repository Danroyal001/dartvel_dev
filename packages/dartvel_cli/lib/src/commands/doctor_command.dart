import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

class DoctorCommand extends Command<void> {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Check your environment and project for common issues.';

  DoctorCommand() {
    argParser.addOption(
      'target',
      allowed: ['webos', 'tizen', 'sony-elinux'],
      help: 'Validate the toolchain for a specific embedded/TV build target',
    );
  }

  @override
  Future<void> run() async {
    final target = argResults?['target'] as String?;
    if (target != null) {
      await _checkTargetToolchain(target);
      return;
    }

    Logger.log('Dartvel Doctor');
    Logger.log('==================================================\n');

    var allGood = true;

    // 1. Check Dart SDK
    allGood = await _checkDartSDK() && allGood;

    // 2. Check Flutter SDK
    allGood = await _checkFlutterSDK() && allGood;

    // 3. Check Git
    allGood = await _checkGit() && allGood;

    Logger.log('\n--------------------------------------------------');
    Logger.log('Optional Tools');
    Logger.log('--------------------------------------------------\n');

    // 4. Check Shorebird (optional)
    await _checkShorebird();

    // 5. Check Codemagic CLI (optional)
    await _checkCodemagic();

    Logger.log('\n--------------------------------------------------');
    Logger.log('Project Status');
    Logger.log('--------------------------------------------------\n');

    // 6. If in a Dartvel project, check project-specific things
    final pubspec = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      await _checkProjectConfig();
    } else {
      Logger.log('[-] Not in a Dartvel project');
      Logger.log(
          '    Run this command in a project directory for additional checks');
    }

    Logger.log('');
    if (allGood) {
      Logger.log('[+] All system checks passed!');
    } else {
      Logger.log('[!] Some checks failed. See above for details.');
    }

    // 7. Run flutter doctor for comprehensive Flutter environment check
    Logger.log('\n==================================================');
    Logger.log('Flutter Doctor Output');
    Logger.log('==================================================\n');
    try {
      final flutterDoctorProcess = await Process.start(
        'flutter',
        ['doctor', '-v'],
        runInShell: true,
      );
      await stdout.addStream(flutterDoctorProcess.stdout);
      await stderr.addStream(flutterDoctorProcess.stderr);
      await flutterDoctorProcess.exitCode;
    } catch (_) {
      Logger.log('[!] Could not run flutter doctor');
    }
  }

  /// Validates the embedder toolchain required for an embedded/TV build target.
  Future<void> _checkTargetToolchain(String target) async {
    Logger.log('Dartvel Doctor — target: $target');
    Logger.log('==================================================\n');

    // Executable each target's build path invokes; webOS builds via `flutter`.
    final executable = switch (target) {
      'tizen' => 'flutter-tizen',
      'sony-elinux' => 'flutter-elinux',
      _ => 'flutter',
    };

    final available = await _isExecutableAvailable(executable);
    if (available) {
      Logger.log('[+] $target embedder: $executable found');
      Logger.log('\n[+] Target $target looks ready to build.');
    } else {
      Logger.log('[!] $target embedder: $executable not found on PATH');
      Logger.log(
        '    Install the $target Flutter embedder before running '
        '`dartvel build $target`.',
      );
    }

    if (target == 'sony-elinux') {
      Logger.log(
        '\n[-] Note: `sony-elinux-iso` and `sony-elinux-img` also require the '
        'configured Sony eLinux image toolchain for image assembly.',
      );
    }
  }

  Future<bool> _isExecutableAvailable(String executable) async {
    try {
      final locator = Platform.isWindows ? 'where' : 'which';
      final result =
          await Process.run(locator, [executable], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkDartSDK() async {
    try {
      final result = await Process.run('dart', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = (result.stdout.toString() + result.stderr.toString())
            .split('\n')
            .first
            .trim();
        Logger.log('[+] Dart SDK: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('[!] Dart SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkFlutterSDK() async {
    try {
      final result =
          await Process.run('flutter', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final version = lines.isNotEmpty ? lines.first.trim() : 'installed';
        Logger.log('[+] Flutter SDK: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('[!] Flutter SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkGit() async {
    try {
      final result = await Process.run('git', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        Logger.log('[+] Git: $version');
        return true;
      }
    } catch (_) {}
    Logger.log('[!] Git: Not found (recommended for version control)');
    return true; // Not critical
  }

  Future<void> _checkShorebird() async {
    try {
      final result =
          await Process.run('shorebird', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        Logger.log('[+] Shorebird: $version');
      } else {
        Logger.log('[-] Shorebird: Not installed (optional for OTA updates)');
      }
    } catch (_) {
      Logger.log('[-] Shorebird: Not installed (optional for OTA updates)');
    }
  }

  Future<void> _checkCodemagic() async {
    try {
      final result =
          await Process.run('codemagic', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        Logger.log('[+] Codemagic CLI: $version');
      } else {
        Logger.log('[-] Codemagic CLI: Not installed (optional for CI/CD)');
      }
    } catch (_) {
      Logger.log('[-] Codemagic CLI: Not installed (optional for CI/CD)');
    }
  }

  Future<void> _checkProjectConfig() async {
    final cwd = Directory.current.path;
    final pubspec = File(p.join(cwd, 'pubspec.yaml'));
    final content = await pubspec.readAsString();
    final hasDartvelConfig =
        RegExp(r'^dartvel:\s*$', multiLine: true).hasMatch(content);
    final hasFlutterDependency =
        content.contains('flutter:') || content.contains('sdk: flutter');

    if (hasDartvelConfig) {
      Logger.log('[+] dartvel: configuration section found');
    } else {
      Logger.log('[!] dartvel: missing pubspec.yaml dartvel: section');
    }

    if (hasFlutterDependency) {
      Logger.log('[+] Flutter dependency configured');
    } else {
      Logger.log('[!] Flutter dependency not found in pubspec.yaml');
    }

    final expectedDirs = [
      'lib/pages',
      'lib/backend/functions',
      'lib/models',
    ];
    for (final dir in expectedDirs) {
      final exists = Directory(p.join(cwd, dir)).existsSync();
      Logger.log(
          '${exists ? '[+]' : '[!]'} $dir ${exists ? 'exists' : 'missing'}');
    }

    final env = File(p.join(cwd, '.env'));
    if (env.existsSync()) {
      Logger.log('[+] .env present');
    } else {
      Logger.log(
          '[-] .env not present; runtime configuration will use defaults');
    }
  }
}
