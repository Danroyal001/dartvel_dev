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
      'web' || 'web-server' => 'web',
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
  late ProcessResult result;
  await dvGeneratePlatformScaffold(
    root: root,
    directory: folderName,
    create: () async {
      result = await run(
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
      return result.exitCode;
    },
  );

  if (result.exitCode != 0) {
    Logger.log('⚠️  Failed to generate $folderName/ scaffold: ${result.stderr}');
    return false;
  }
  return true;
}

/// Runs [create], a `flutter create` or a vendor embedder's `create`, and
/// keeps only the platform [directory] it generates.
///
/// Every one of those commands also writes files outside the platform folder
/// into a project that did not ask for them: a counter-app
/// `test/widget_test.dart` whose `MyApp` does not exist (so the project's own
/// analysis fails), `.metadata`, an IDE `.iml`, and `lib/main.dart` when the
/// project has none. Whatever was not there before is removed afterwards,
/// with the directories it alone filled -- also when [create] fails or throws
/// part-way, because a failed build must not leave the project changed
/// either. What the project already had is never touched.
Future<int> dvGeneratePlatformScaffold({
  required String root,
  required String directory,
  required Future<int> Function() create,
}) async {
  final Set<String> filesBefore = _projectFiles(root);
  final Set<String> directoriesBefore = _projectDirectories(root);
  try {
    return await create();
  } finally {
    for (final String added in _projectFiles(root).difference(filesBefore)) {
      if (p.split(added).first == directory) continue;
      final File file = File(p.join(root, added));
      if (file.existsSync()) file.deleteSync();
    }
    final List<String> addedDirectories =
        _projectDirectories(root).difference(directoriesBefore).toList()
          // Deepest first, so a parent is empty by the time it is reached.
          ..sort((String a, String b) => p.split(b).length.compareTo(p.split(a).length));
    for (final String added in addedDirectories) {
      if (p.split(added).first == directory) continue;
      final Directory dir = Directory(p.join(root, added));
      if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
    }
  }
}

/// Names [_projectFiles] and [_projectDirectories] never look inside: build
/// output, tool state, and the native folders, which are ephemeral.
const Set<String> _notProjectFiles = <String>{
  'build', '.dart_tool', '.git', 'android', 'ios', 'linux', 'macos', 'windows', 'web',
  'tizen', 'elinux', 'webos', 'tvos',
};

/// The project's own directories, relative to [root], as [_projectFiles]
/// sees them.
Set<String> _projectDirectories(String root) {
  final Set<String> directories = <String>{};
  final Directory dir = Directory(root);
  if (!dir.existsSync()) return directories;
  for (final FileSystemEntity entry in dir.listSync()) {
    if (entry is! Directory || _notProjectFiles.contains(p.basename(entry.path))) continue;
    directories.add(p.basename(entry.path));
    for (final FileSystemEntity inner in entry.listSync(recursive: true, followLinks: false)) {
      if (inner is Directory) directories.add(p.relative(inner.path, from: root));
    }
  }
  return directories;
}

/// The project's own files, relative to [root]: everything but build output,
/// tool state and the native folders, which are ephemeral.
Set<String> _projectFiles(String root) {
  final Set<String> files = <String>{};
  final Directory dir = Directory(root);
  if (!dir.existsSync()) return files;
  for (final FileSystemEntity entry in dir.listSync()) {
    final String name = p.basename(entry.path);
    if (_notProjectFiles.contains(name)) continue;
    if (entry is File) {
      files.add(name);
    } else if (entry is Directory) {
      for (final FileSystemEntity inner in entry.listSync(recursive: true, followLinks: false)) {
        if (inner is File) files.add(p.relative(inner.path, from: root));
      }
    }
  }
  return files;
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
