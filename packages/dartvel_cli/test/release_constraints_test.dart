// A package's constraint on its siblings has to admit the version they are at.
//
// dartvel_dev 0.3.1 shipped depending on dartvel_core ^0.2.1. For a 0.x
// version a caret means ">=0.2.1 <0.3.0", so it excludes the 0.3.1 that was
// published beside it -- a user installing dartvel_dev 0.3.1 resolved
// dartvel_core 0.2.1 and none of what that release was for.
//
// Nothing caught it. `dart pub publish --dry-run` resolves against
// pubspec_overrides.yaml, which points every sibling at a local path, so the
// stale constraint is never exercised. The dry run is green precisely because
// it is not testing what a user gets.
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Every package in this repository, by name, with its declared version.
Map<String, String> workspaceVersions(Directory packages) {
  final Map<String, String> out = <String, String>{};
  for (final FileSystemEntity entity in packages.listSync()) {
    if (entity is! Directory) continue;
    final File pubspec = File('${entity.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final YamlMap doc = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    out['${doc['name']}'] = '${doc['version']}';
  }
  return out;
}

/// The hosted constraint [package] declares on each Dartvel sibling.
Map<String, String> siblingConstraints(Directory packages, String package) {
  final YamlMap doc =
      loadYaml(File('${packages.path}/$package/pubspec.yaml').readAsStringSync())
          as YamlMap;
  final Object? deps = doc['dependencies'];
  if (deps is! YamlMap) return <String, String>{};

  final Map<String, String> out = <String, String>{};
  for (final MapEntry<Object?, Object?> entry in deps.entries) {
    final String name = '${entry.key}';
    if (!name.startsWith('dartvel_')) continue;
    final Object? value = entry.value;
    // Either `dartvel_core: ^0.3.0` or the `version:`/`hosted:` long form.
    if (value is String) {
      out[name] = value;
    } else if (value is YamlMap && value['version'] != null) {
      out[name] = '${value['version']}';
    }
  }
  return out;
}

/// The workspace's `packages/` directory, found by walking up.
///
/// Not a relative '..' from the current directory: this test is run both from
/// the package and from the repository root by tool/publish.sh, and a relative
/// path silently resolves to nothing in one of them -- which makes the whole
/// file assert about an empty map and pass.
Directory findPackagesDir() {
  Directory dir = Directory.current;
  for (int depth = 0; depth < 6; depth += 1) {
    final Directory candidate = Directory('${dir.path}/packages');
    if (Directory('${candidate.path}/dartvel_core').existsSync()) {
      return candidate;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('could not find the packages/ directory from '
      '${Directory.current.path}');
}

void main() {
  final Directory packages = findPackagesDir();
  final Map<String, String> versions = workspaceVersions(packages);

  test('the workspace has the packages this test is about', () {
    // If the layout moves, the loop below would silently assert nothing.
    expect(versions.keys, contains('dartvel_core'));
    expect(versions.length, greaterThanOrEqualTo(5));
  });

  for (final String package in versions.keys) {
    final Map<String, String> constraints =
        siblingConstraints(packages, package);
    if (constraints.isEmpty) continue;

    for (final MapEntry<String, String> entry in constraints.entries) {
      test('$package accepts the ${entry.key} in this repository', () {
        final String? siblingVersion = versions[entry.key];
        expect(siblingVersion, isNotNull,
            reason: '$package depends on ${entry.key}, which is not here');

        final VersionConstraint constraint =
            VersionConstraint.parse(entry.value);
        final Version actual = Version.parse(siblingVersion!);

        expect(
          constraint.allows(actual),
          isTrue,
          reason: '$package declares ${entry.key}: ${entry.value}, which does '
              'not admit ${entry.key} $actual. Published together, a user '
              'gets an older ${entry.key} than the one this release was '
              'built against.',
        );
      });
    }
  }
}
