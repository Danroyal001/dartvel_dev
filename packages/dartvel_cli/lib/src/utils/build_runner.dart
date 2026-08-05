import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

bool hasBuildRunnerDependency(String root) {
  return hasPubDependency(root, 'build_runner');
}

bool hasPubDependency(String root, String dependencyName) {
  final pubspec = _readPubspec(root);
  if (pubspec == null) return false;

  const dependencySections = <String>[
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ];
  for (final sectionName in dependencySections) {
    final sectionValue = pubspec[sectionName];
    final YamlMap? section = sectionValue is YamlMap ? sectionValue : null;
    if (section != null && section.containsKey(dependencyName)) {
      return true;
    }
  }
  return false;
}

/// Reads and parses `pubspec.yaml`, or null when it is absent or not a map.
YamlMap? readPubspecYaml(String root) => _readPubspec(root);

YamlMap? _readPubspec(String root) {
  final file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final parsed = loadYaml(file.readAsStringSync());
  return parsed is YamlMap ? parsed : null;
}
