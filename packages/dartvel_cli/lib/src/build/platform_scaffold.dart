library dartvel_cli.build.platform_scaffold;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import '../utils/logger.dart';

typedef BuildProcessRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

/// Maps a Dartvel target platform name to the platform name `flutter create --platforms=<p>` accepts,
/// or null if this target is not built via `flutter create`.
String? dvFlutterPlatformFor(String platform) => switch (platform) {
      'android' || 'fireos' => 'android',
      'ios' => 'ios',
      'linux' => 'linux',
      'macos' => 'macos',
      'windows' => 'windows',
      'web' || 'web-server' || 'chrome-extension' || 'firefox-extension' => 'web',
      _ => null,
    };

/// The directory name in the project root corresponding to the platform scaffold,
/// or null if none.
String? dvPlatformDirectoryFor(String platform) => dvFlutterPlatformFor(platform);

/// Resolves the platform name from a device id/name (e.g. 'chrome' -> 'web',
/// 'web-server' -> 'web', 'linux' -> 'linux', 'macos' -> 'macos',
/// 'windows' -> 'windows', etc.) or null if unknown.
String? dvPlatformForDevice(
  String device, {
  List<Map<String, Object?>> detected = const <Map<String, Object?>>[],
}) {
  for (final Map<String, Object?> d in detected) {
    if (d['id'] == device || d['name'] == device) {
      final String targetPlatform =
          (d['targetPlatform'] ?? '').toString().toLowerCase();
      if (targetPlatform.startsWith('android')) return 'android';
      if (targetPlatform.startsWith('ios')) return 'ios';
      if (targetPlatform.startsWith('darwin') ||
          targetPlatform.startsWith('macos')) {
        return 'macos';
      }
      if (targetPlatform.startsWith('linux')) return 'linux';
      if (targetPlatform.startsWith('windows')) return 'windows';
      if (targetPlatform.contains('web')) return 'web';
    }
  }

  final String lower = device.toLowerCase();
  if (lower == 'chrome' || lower == 'edge' || lower.contains('web')) {
    return 'web';
  }
  if (lower == 'linux') return 'linux';
  if (lower == 'macos' || lower == 'darwin') return 'macos';
  if (lower == 'windows') return 'windows';
  if (lower == 'android' || lower.startsWith('emulator-')) return 'android';
  if (lower == 'ios' || lower.contains('iphone') || lower.contains('ipad')) {
    return 'ios';
  }
  if (lower.contains('android')) return 'android';
  return null;
}

/// Generates the ephemeral native platform folder for [platform] when missing.
///
/// Native folders (android/, ios/, web/, linux/, windows/, macos/) are ephemeral build
/// artifacts in Dartvel: `dartvel create` creates none of them. When a build or dev run
/// targets a platform whose folder does not exist, Dartvel generates it quietly using
/// `flutter create --platforms=<p> --project-name <name> --org <org> .` before any native
/// writers (splash, launcher identity, deep links, kiosk, widgets, file storage) run.
Future<bool> dvEnsurePlatformScaffold({
  required String root,
  required String platform,
  BuildProcessRun? processRun,
}) async {
  final String? flutterPlatform = dvFlutterPlatformFor(platform);
  if (flutterPlatform == null) return true;

  final String folderName = dvPlatformDirectoryFor(platform)!;
  final Directory platformDir = Directory(p.join(root, folderName));
  if (platformDir.existsSync()) return true;

  final String projectName = _readProjectName(root) ?? p.basename(root);
  final String? org = _readOrg(root);

  Logger.log('   No $folderName/ scaffold; generating it...');
  final run = processRun ?? _defaultProcessRun;
  final ProcessResult result = await run(
    'flutter',
    <String>[
      'create',
      '--platforms=$flutterPlatform',
      '--project-name',
      projectName,
      if (org != null && org.isNotEmpty) ...<String>['--org', org],
      '.',
    ],
    workingDirectory: root,
    runInShell: true,
  );

  if (result.exitCode != 0) {
    Logger.log('⚠️  Failed to generate $folderName/ scaffold: ${result.stderr}');
    return false;
  }
  return true;
}

Future<ProcessResult> _defaultProcessRun(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell = true,
}) =>
    Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );

String? _readProjectName(String root) {
  final File file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  try {
    final doc = loadYaml(file.readAsStringSync());
    final name = doc is Map ? doc['name'] : null;
    return name is String ? name : null;
  } catch (_) {
    return null;
  }
}

String? _readOrg(String root) {
  final File file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  try {
    final doc = loadYaml(file.readAsStringSync());
    final dartvel = doc is Map ? doc['dartvel'] : null;
    if (dartvel is Map && dartvel['org'] is String) {
      return dartvel['org'] as String;
    }
    return null;
  } catch (_) {
    return null;
  }
}
