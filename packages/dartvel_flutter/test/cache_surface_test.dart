// What a page imports reaches DV.Cache's four calls and the adapters, and
// not the cache's machinery.
//
// dartvel.cache names the store DV.Cache uses; DV.Cache.withAdapter switches
// store in code, so the adapters are the application's to construct. The
// Redis client, the tag registry, the config reader and DVCacheRuntime are
// how the framework delivers a cache, and stay out.
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
  test('a page reaches DV.Cache and the adapters', () async {
    // The control: if this stops holding, the checks below pass because
    // nothing resolves rather than because the machinery is hidden.
    final String output = await analyzed('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

Future<void> use() async {
  await DV.Cache.set('k', 1, ttl: const Duration(minutes: 1), tags: <String>['t']);
  final int? read = await DV.Cache.get<int>(
    'k',
    compute: () async => 1,
    ttl: const Duration(minutes: 1),
    tags: <String>['t'],
    staleFor: const Duration(minutes: 1),
  );
  final bool cached = await DV.Cache.has('k');
  await DV.Cache.delete(key: 'k');
  await DV.Cache.delete(tag: 't');
  await DV.Cache.delete(all: true);
  print('\$read \$cached');
}

Future<void> switched(DVDatabaseAdapter database) async {
  final List<DVCacheAdapter> stores = <DVCacheAdapter>[
    DVMemoryCacheAdapter(),
    DVDatabaseCacheAdapter(database),
    await DVRedisCacheAdapter.connect('redis://127.0.0.1:6379'),
    DVMemcachedCacheAdapter(host: '127.0.0.1'),
    DVDistributedCacheAdapter(nodes: <String, DVCacheAdapter>{
      'a': DVMemoryCacheAdapter(),
    }),
  ];
  for (final DVCacheAdapter store in stores) {
    final DVCacheView cache = DV.Cache.withAdapter(store);
    await cache.set('k', 1, tags: <String>['t']);
    await cache.get<int>('k', compute: () async => 1);
    await cache.has('k');
    await cache.delete(tag: 't');
  }
}
''');
    expect(output, isNot(contains(' error ')));
  }, timeout: const Timeout(Duration(minutes: 3)));

  // DV.Cache is four calls. Everything else was either folded into them as an
  // option or is the framework's machinery, and a page reaching for one of
  // these must not compile.
  const List<String> gone = <String>[
    'remember',
    'staleWhileRevalidate',
    'tag',
    'revalidateTag',
    'clear',
    'lock',
    'purgeExpired',
    'keysForTag',
    'tags',
    'configure',
    'configureGlobal',
    'adapter',
    'globalGet',
    'globalSet',
    'globalDelete',
    'globalTag',
    'globalRevalidateTag',
  ];
  test('DV.Cache has no member but the four calls and withAdapter',
      () async {
    final String output = await analyzed('''
import 'package:dartvel_flutter/dartvel_flutter.dart';

${[for (final String name in gone) 'Object? get probe_$name => DV.Cache.$name;'].join('\n')}
''');
    for (int i = 0; i < gone.length; i++) {
      // The probes start on line 3, one per line.
      expect(
        output,
        contains('probe.dart:${i + 3}:'),
        reason: 'DV.Cache.${gone[i]} still resolves from a page',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  for (final String name in <String>[
    'DVCacheRuntime',
    'DVRedisClient',
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
