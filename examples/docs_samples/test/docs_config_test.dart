// The pubspec blocks shown on the docs pages are read the way Dartvel reads
// them, so a block the docs show cannot be one Dartvel refuses.
import 'dart:io';

import 'package:docs_samples/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final YamlMap dartvel =
      (loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap)['dartvel']
          as YamlMap;

  test('the platform API block is read', () {
    final DVPlatformApiConfig config = dartvelPlatformApi!;
    expect(config.ratePlans, contains('standard'));
  });

  test('the infra block is read', () {
    final Map<String, DVInfraManifest> environments =
        DVInfraManifest.fromConfig(dartvel['infra']);
    expect(environments.keys, <String>['production']);
  });
}
