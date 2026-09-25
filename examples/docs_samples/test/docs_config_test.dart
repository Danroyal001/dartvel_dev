// The pubspec blocks shown on the docs pages are read the way Dartvel reads
// them, so a block the docs show cannot be one Dartvel refuses.
import 'dart:io';

// The cache block's reader is the framework's, not in the client barrel.
import 'package:dartvel_core/dartvel.dart' show DVCacheConfig, DVCacheStore;
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

  test('the cache block is read', () {
    final DVCacheConfig cache = DVCacheConfig.read(dartvel['cache'])!;
    expect(cache.store, DVCacheStore.redis);
    expect(cache.urlVariable, 'REDIS_URL');
    expect(cache.prefix, 'shop:');
  });

  test('the infra block is read', () {
    final Map<String, DVInfraManifest> environments =
        DVInfraManifest.fromConfig(dartvel['infra']);
    expect(environments.keys, <String>['production']);
  });
}
