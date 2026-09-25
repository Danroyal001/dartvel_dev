// The cache's machinery is not in the surface a page imports.
//
// An application reads and writes DV.Cache and names its store in
// dartvel.cache; it never constructs an adapter or a Redis client, and a
// page could not reach Redis from a browser if it tried. So the adapters stay
// in dartvel_core for the framework, the generated server and tests, and out
// of the Flutter barrel.
//
// The check analyzes a file that imports what a page imports, so it fails
// when a name comes back by any route rather than when one export line
// changes.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<String> analyzed(String source) async {
  final Directory scratch = Directory(
    p.join(
      Directory.current.path,
      '.dart_tool',
      'dv_cache_surface_check',
      'probe_${DateTime.now().microsecondsSinceEpoch}',
    ),
  )..createSync(recursive: true);
  addTearDown(() {
    if (scratch.parent.existsSync()) scratch.parent.deleteSync(recursive: true);
  });
  final File probe = File(p.join(scratch.path, 'probe.dart'))
    ..writeAsStringSync(source);
  final ProcessResult result = await Process.run(
    'dart',
    <String>['analyze', '--no-fatal-warnings', probe.path],
  );
  return '${result.stdout}${result.stderr}';
}

void main() {
  test('a page reaches DV.Cache', () async {
    // The control: if this stops holding, the checks below pass because
    // nothing resolves rather than because the machinery is hidden.
    final String output = await analyzed('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

Future<void> use() async {
  await DV.Cache.set('k', 1, ttl: const Duration(minutes: 1));
  await DV.Cache.remember<int>('k', () async => 1, tags: <String>['t']);
}
''');
    expect(output, isNot(contains(' error ')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  for (final String name in <String>[
    'DVMemoryCacheAdapter',
    'DVDatabaseCacheAdapter',
    'DVRedisCacheAdapter',
    'DVRedisClient',
    'DVMemcachedCacheAdapter',
    'DVDistributedCacheAdapter',
    'DVCacheTags',
    'DVCacheConfig',
  ]) {
    test('a page cannot name $name', () async {
      final String output = await analyzed('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

Type get machinery => $name;
''');
      expect(output, contains('undefined_identifier'));
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
