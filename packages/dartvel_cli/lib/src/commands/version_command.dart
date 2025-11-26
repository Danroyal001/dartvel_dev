import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/logger.dart';

class VersionCommand extends Command<void> {
  @override
  final String name = 'version';

  @override
  final String description = 'Print the current version of Dartvel CLI.';

  @override
  Future<void> run() async {
    // Try to read version from pubspec.yaml in the package
    // This is tricky because we are running as a compiled executable or script.
    // If running as script, we can find the pubspec relative to the script.
    // But for now, let's hardcode it or try to find it.
    // Actually, the best way is to have a constant generated or updated.
    // For now, I'll read it from the pubspec if available, or fallback.

    String version = '0.1.0'; // Fallback

    try {
      // Assuming we are running from source or the pubspec is nearby
      // When installed globally, this might not work.
      // A better approach for a real CLI is to bake the version in.
      // But since we are running `dart run .../main.dart`, we can find it.
      final scriptPath = Platform.script.toFilePath();
      final pkgRoot = p.dirname(p.dirname(p.dirname(scriptPath)));
      final pubspec = File(p.join(pkgRoot, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
        version = yaml['version']?.toString() ?? version;
      }
    } catch (_) {}

    Logger.log('Dartvel CLI: $version');
    Logger.log('Dart SDK:    ${Platform.version.split(' ').first}');

    // Flutter version
    try {
      final res = await Process.run('flutter', ['--version']);
      if (res.exitCode == 0) {
        // Output format: Flutter 3.19.0 • channel stable • ...
        final line = (res.stdout as String).split('\n').first;
        Logger.log('Flutter:     $line');
      } else {
        Logger.log('Flutter:     (not installed)');
      }
    } catch (_) {
      Logger.log('Flutter:     (not installed)');
    }

    // Shorebird version
    try {
      final res = await Process.run('shorebird', ['--version']);
      if (res.exitCode == 0) {
        Logger.log('Shorebird:   ${(res.stdout as String).trim()}');
      } else {
        Logger.log('Shorebird:   (not installed)');
      }
    } catch (_) {
      Logger.log('Shorebird:   (not installed)');
    }
  }
}
