import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/logger.dart';

/// The version this build of the CLI is.
///
/// A constant rather than something read off disk at run time. Discovery
/// walked up from the working directory looking for any pubspec.yaml, which is
/// right when the CLI runs from its own source tree and wrong everywhere else:
/// a compiled binary invoked inside someone's project finds *their* pubspec
/// and reports *their* app's version. With nothing above it, it fell back to a
/// hardcoded number that had already drifted, and the released 0.2.1 binary
/// announced itself as 0.2.0.
///
/// A test asserts this equals what pubspec.yaml declares, so the two cannot
/// come apart without the suite saying so.
const String dartvelCliVersion = '0.3.1';

class VersionCommand extends Command<void> {
  @override
  final String name = 'version';

  @override
  final String description = 'Print the current version of Dartvel CLI.';

  @override
  Future<void> run() async {
    const version = dartvelCliVersion;

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

String? readDartvelCliVersion() {
  final candidates = <Directory>[
    Directory.current,
    if (Platform.script.scheme == 'file')
      File(Platform.script.toFilePath()).parent,
  ];

  for (final candidate in candidates) {
    final version = _findVersionAbove(candidate);
    if (version != null) return version;
  }
  return null;
}

String? _findVersionAbove(Directory start) {
  Directory current = start.absolute;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final version = _readVersionFromPubspec(pubspec);
      if (version != null) return version;
    }
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
}

String? _readVersionFromPubspec(File pubspec) {
  final yaml = loadYaml(pubspec.readAsStringSync());
  if (yaml is! YamlMap) return null;
  if (yaml['name'] != 'dartvel_cli') return null;
  return yaml['version']?.toString();
}
