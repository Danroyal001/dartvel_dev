/// Finding the package that provides a build target, and handing it the build.
///
/// Dart cannot load code into a running executable, so a target package is
/// not loaded: it ships its own executable, which is this CLI with its
/// targets registered (see `dvRunWithTargets`). `dartvel build <target>`
/// finds the package through the project's resolved dependencies and runs
/// the same command through it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The manifest a target package carries at its root.
const String dvTargetManifestFile = 'dartvel_targets.yaml';

/// Set in the environment of a delegated run, so a package that declares a
/// target and does not register it is reported rather than delegated to
/// again, forever.
const String dvTargetsDelegatedVariable = 'DARTVEL_TARGETS_DELEGATED';

/// A package in the project's dependencies that provides build targets.
class DVTargetPackage {
  const DVTargetPackage({
    required this.name,
    required this.root,
    required this.executable,
    required this.targets,
  });

  /// The package's name, as `dart run <name>:<executable>` takes it.
  final String name;

  /// Where the package's files are.
  final String root;

  /// The executable under the package's `bin/` that registers its targets.
  final String executable;

  /// Every target name the manifest declares.
  final List<String> targets;
}

/// The target packages [projectRoot] depends on, read from its
/// `.dart_tool/package_config.json`. Empty before `pub get` has run, and for
/// a package whose manifest cannot be read: a broken manifest in one package
/// must not stop a free build.
List<DVTargetPackage> dvTargetPackages(String projectRoot) {
  final File config =
      File(p.join(projectRoot, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return const <DVTargetPackage>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(config.readAsStringSync());
  } on FormatException {
    return const <DVTargetPackage>[];
  }
  final Object? packages = decoded is Map ? decoded['packages'] : null;
  if (packages is! List) return const <DVTargetPackage>[];
  final List<DVTargetPackage> found = <DVTargetPackage>[];
  for (final Object? entry in packages) {
    if (entry is! Map) continue;
    final Object? name = entry['name'];
    final Object? rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String) continue;
    final Uri base = config.parent.uri;
    final Uri resolved = base.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
    if (resolved.scheme != 'file') continue;
    final String root = p.normalize(resolved.toFilePath());
    final DVTargetPackage? package = dvReadTargetManifest(name, root);
    if (package != null) found.add(package);
  }
  return found;
}

/// The manifest of the package [name] at [root], or null when it has none or
/// it is not one Dartvel can read.
DVTargetPackage? dvReadTargetManifest(String name, String root) {
  final File manifest = File(p.join(root, dvTargetManifestFile));
  if (!manifest.existsSync()) return null;
  final Object? yaml;
  try {
    yaml = loadYaml(manifest.readAsStringSync());
  } on Object {
    return null;
  }
  if (yaml is! Map) return null;
  final Object? executable = yaml['executable'];
  final Object? targets = yaml['targets'];
  if (executable is! String || targets is! List) return null;
  return DVTargetPackage(
    name: name,
    root: root,
    executable: executable,
    targets: <String>[for (final Object? target in targets) '$target'],
  );
}

/// The package that provides [target] to [projectRoot], or null.
DVTargetPackage? dvTargetPackageFor(String projectRoot, String target) {
  for (final DVTargetPackage package in dvTargetPackages(projectRoot)) {
    if (package.targets.contains(target)) return package;
  }
  return null;
}

/// Whether this process was started by [dvDelegateToTargetPackage].
bool dvIsDelegatedRun([Map<String, String>? environment]) =>
    (environment ?? Platform.environment)[dvTargetsDelegatedVariable] == '1';

/// Runs `dart run <package>:<executable> <arguments>` in [projectRoot] with
/// the terminal handed over, and returns its exit code.
Future<int> dvDelegateToTargetPackage(
  DVTargetPackage package,
  List<String> arguments, {
  required String projectRoot,
}) async {
  final Process process = await Process.start(
    'dart',
    <String>['run', '${package.name}:${package.executable}', ...arguments],
    workingDirectory: projectRoot,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
    environment: <String, String>{dvTargetsDelegatedVariable: '1'},
  );
  return process.exitCode;
}
