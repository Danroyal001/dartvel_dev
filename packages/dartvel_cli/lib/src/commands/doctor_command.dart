import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

class DoctorCommand extends Command<void> {
  @override
  final String name = 'doctor';

  @override
  final String description =
      'Check your environment and project for common issues.';

  @override
  Future<void> run() async {
    print('Dartvel Doctor');
    print('==================================================\n');

    var allGood = true;

    // 1. Check Dart SDK
    allGood = await _checkDartSDK() && allGood;

    // 2. Check Flutter SDK
    allGood = await _checkFlutterSDK() && allGood;

    // 3. Check Git
    allGood = await _checkGit() && allGood;

    print('\n--------------------------------------------------');
    print('Optional Tools');
    print('--------------------------------------------------\n');

    // 4. Check Shorebird (optional)
    await _checkShorebird();

    // 5. Check Codemagic CLI (optional)
    await _checkCodemagic();

    print('\n--------------------------------------------------');
    print('Project Status');
    print('--------------------------------------------------\n');

    // 6. If in a Dartvel project, check project-specific things
    final pubspec = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      await _checkProjectConfig();
    } else {
      print('[-] Not in a Dartvel project');
      print(
          '    Run this command in a project directory for additional checks');
    }

    print('');
    if (allGood) {
      print('[+] All system checks passed!');
    } else {
      print('[!] Some checks failed. See above for details.');
    }

    // 7. Run flutter doctor for comprehensive Flutter environment check
    print('\n==================================================');
    print('Flutter Doctor Output');
    print('==================================================\n');
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
      print('[!] Could not run flutter doctor');
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
        print('[+] Dart SDK: $version');
        return true;
      }
    } catch (_) {}
    print('[!] Dart SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkFlutterSDK() async {
    try {
      final result =
          await Process.run('flutter', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final version = lines.isNotEmpty ? lines.first.trim() : 'installed';
        print('[+] Flutter SDK: $version');
        return true;
      }
    } catch (_) {}
    print('[!] Flutter SDK: Not found or not in PATH');
    return false;
  }

  Future<bool> _checkGit() async {
    try {
      final result = await Process.run('git', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        print('[+] Git: $version');
        return true;
      }
    } catch (_) {}
    print('[!] Git: Not found (recommended for version control)');
    return true; // Not critical
  }

  Future<void> _checkShorebird() async {
    try {
      final result =
          await Process.run('shorebird', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        print('[+] Shorebird: $version');
      } else {
        print('[-] Shorebird: Not installed (optional for OTA updates)');
      }
    } catch (_) {
      print('[-] Shorebird: Not installed (optional for OTA updates)');
    }
  }

  Future<void> _checkCodemagic() async {
    try {
      final result =
          await Process.run('codemagic', ['--version'], runInShell: true);
      if (result.exitCode == 0) {
        final version = result.stdout.toString().trim();
        print('[+] Codemagic CLI: $version');
      } else {
        print('[-] Codemagic CLI: Not installed (optional for CI/CD)');
      }
    } catch (_) {
      print('[-] Codemagic CLI: Not installed (optional for CI/CD)');
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
      print('[+] dartvel: configuration section found');
    } else {
      print('[!] dartvel: missing pubspec.yaml dartvel: section');
    }

    if (hasFlutterDependency) {
      print('[+] Flutter dependency configured');
    } else {
      print('[!] Flutter dependency not found in pubspec.yaml');
    }

    final expectedDirs = [
      'lib/pages',
      'lib/backend/functions',
      'lib/models',
    ];
    for (final dir in expectedDirs) {
      final exists = Directory(p.join(cwd, dir)).existsSync();
      print('${exists ? '[+]' : '[!]'} $dir ${exists ? 'exists' : 'missing'}');
    }

    final env = File(p.join(cwd, '.env'));
    if (env.existsSync()) {
      print('[+] .env present');
    } else {
      print('[-] .env not present; runtime configuration will use defaults');
    }
  }
}
