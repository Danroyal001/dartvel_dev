// Every package in this repository declared `sdk: ">=3.4.0 <4.0.0"`, and none
// of them could be used on Dart 3.4.
//
// dartvel_flutter depends on mix, whose own floor is far higher;
// dartvel_shelf's build hook needs `code_assets`. A user on 3.4 therefore got
// a resolution failure naming a transitive package, instead of the one
// sentence that would have helped: your Dart is too old.
//
// This asserts the invariant rather than a number: no package may declare a
// floor below the highest floor in its own resolved dependency graph. That
// derives the answer from the resolution that actually happened, so it stays
// true when a dependency raises its floor — which is precisely the event that
// broke this last time, and which a hard-coded version here would sleep
// through.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

final _repoRoot = _findRepoRoot();

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/NEW_SPEC.md').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('could not locate the repository root');
    }
    dir = parent;
  }
  return dir;
}

/// The lower bound of an `environment: sdk:` constraint, or null when the
/// pubspec declares none.
Version? _declaredFloor(File pubspec) {
  if (!pubspec.existsSync()) return null;
  final lines = pubspec.readAsLinesSync();
  var inEnvironment = false;
  for (final line in lines) {
    if (line.startsWith('environment:')) {
      inEnvironment = true;
      continue;
    }
    if (inEnvironment) {
      // Any unindented line ends the block.
      if (line.isNotEmpty && !line.startsWith(RegExp(r'\s'))) break;
      final match = RegExp(r'''sdk:\s*['"]?([^'"]*)['"]?''').firstMatch(line);
      if (match == null) continue;
      final bound =
          RegExp(r'>=\s*(\d+)\.(\d+)\.(\d+)').firstMatch(match.group(1)!);
      if (bound == null) return null;
      return Version(
        int.parse(bound.group(1)!),
        int.parse(bound.group(2)!),
        int.parse(bound.group(3)!),
      );
    }
  }
  return null;
}

/// Every package resolved for [packageDir], read from the package config that
/// `pub get` wrote. This covers hosted, git and path dependencies uniformly,
/// which matters here because Dartvel's mix is a git fork rather than the
/// published package.
List<Directory> _resolvedPackages(Directory packageDir) {
  final config = File('${packageDir.path}/.dart_tool/package_config.json');
  if (!config.existsSync()) return const [];
  final decoded =
      jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final packages = decoded['packages'] as List<dynamic>;
  return [
    for (final entry in packages.cast<Map<String, dynamic>>())
      Directory.fromUri(
        Uri.parse(entry['rootUri'] as String).hasScheme
            ? Uri.parse(entry['rootUri'] as String)
            : config.parent.uri.resolve(entry['rootUri'] as String),
      ),
  ];
}

class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);
  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

void main() {
  final packageNames = Directory('${_repoRoot.path}/packages')
      .listSync()
      .whereType<Directory>()
      .map((d) => d.path.split('/').last)
      .toList()
    ..sort();

  test('the repository has packages to check', () {
    expect(packageNames, isNotEmpty);
  });

  // The project rule is a single floor, not merely a sufficient one. Two
  // floors that disagreed is what let webOS be recorded as unproven when its
  // Dart could not resolve dependencies at all: with 3.9 and 3.11 both written
  // down, the lower number was the one that got reasoned from. A per-package
  // floor is defensible on its own terms and is still refused here, because
  // the cost being avoided is a wrong conclusion rather than a wrong number.
  test('every package declares the same floor', () {
    final floors = <String, Version?>{
      'pubspec.yaml': _declaredFloor(File('${_repoRoot.path}/pubspec.yaml')),
      // Discovered rather than listed. A new example is exactly the kind of
      // thing that gets added with a copied pubspec and an old floor, and a
      // hard-coded list here would not notice.
      for (final example in Directory('${_repoRoot.path}/examples')
          .listSync()
          .whereType<Directory>())
        'examples/${example.path.split('/').last}':
            _declaredFloor(File('${example.path}/pubspec.yaml')),
      for (final name in packageNames)
        name: _declaredFloor(
            File('${_repoRoot.path}/packages/$name/pubspec.yaml')),
    }..removeWhere((_, floor) => floor == null);

    final distinct = floors.values.map((v) => v.toString()).toSet();
    expect(
      distinct,
      hasLength(1),
      reason: 'Dartvel declares one SDK floor everywhere. Found '
          '${distinct.toList()..sort()} across '
          '${floors.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
    );
  });

  for (final name in packageNames) {
    final packageDir = Directory('${_repoRoot.path}/packages/$name');

    test('$name declares a floor its dependencies can actually meet', () {
      final declared = _declaredFloor(File('${packageDir.path}/pubspec.yaml'));
      expect(declared, isNotNull,
          reason: '$name declares no SDK lower bound at all');

      final resolved = _resolvedPackages(packageDir);
      if (resolved.isEmpty) {
        markTestSkipped('$name has not been resolved; run `pub get` first');
        return;
      }

      Version? highest;
      var demandedBy = '';
      for (final dependency in resolved) {
        final floor = _declaredFloor(File('${dependency.path}/pubspec.yaml'));
        if (floor == null) continue;
        if (highest == null || floor.compareTo(highest) > 0) {
          highest = floor;
          demandedBy = dependency.path.split('/').last;
        }
      }
      if (highest == null) return;

      expect(
        declared!.compareTo(highest) >= 0,
        isTrue,
        reason: '$name declares >=$declared, but $demandedBy in its own '
            'resolved dependencies requires >=$highest. A user on $declared '
            'cannot resolve this package, and the error they get names '
            '$demandedBy rather than their Dart version.',
      );
    });
  }
}
