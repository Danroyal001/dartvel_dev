import 'dart:convert';

import 'package:dartvel_core/src/updates/ota_updates.dart';
import 'package:dartvel_core/src/web/rendered_page_cache.dart';
import 'package:test/test.dart';

void main() {
  test('GET validators use weak comparison across compression variants', () {
    expect(dvRenderedPageNotModified('"other", W/"same"', '"same"'), isTrue);
    expect(dvRenderedPageNotModified('"same"', 'W/"same"'), isTrue);
    expect(dvRenderedPageNotModified('*', 'W/"same"'), isTrue);
    expect(dvRenderedPageNotModified('"other"', 'W/"same"'), isFalse);
  });

  test(
    'query, host, locale and theme partition entries; validators do not',
    () {
      String key(String uri, Map<String, String> headers) =>
          dvRenderedPageKey('site', Uri.parse(uri), headers);
      final original = key('http://a/login?q=one', {
        'accept-language': 'en',
        'x-dartvel-theme': 'light',
      });
      expect(
        key('http://a/login?q=two', {
          'accept-language': 'en',
          'x-dartvel-theme': 'light',
        }),
        isNot(original),
      );
      expect(
        key('http://b/login?q=one', {
          'accept-language': 'en',
          'x-dartvel-theme': 'light',
        }),
        isNot(original),
      );
      expect(
        key('http://a/login?q=one', {
          'accept-language': 'fr',
          'x-dartvel-theme': 'light',
        }),
        isNot(original),
      );
      expect(
        key('http://a/login?q=one', {
          'accept-language': 'en',
          'x-dartvel-theme': 'dark',
        }),
        isNot(original),
      );
      expect(
        key('http://a/login?q=one', {
          'x-dartvel-theme': 'light',
          'accept-language': 'en',
          'if-none-match': 'old',
        }),
        original,
      );
    },
  );
  test('a fill started before purge cannot repopulate the cache', () {
    final cache = DVRenderedPageCache();
    final before = dvRenderedPagesGeneration;
    dvPurgeRenderedPages();
    cache.put('old', [1], {}, status: 200, generation: before);
    expect(cache.get('old'), isNull);
  });

  test(
    'successful OTA installer purges; failed installer retains documents',
    () async {
      final cache = DVRenderedPageCache();
      cache.put('page', [1], {}, status: 200);
      await OtaUpdateManager(updateInstaller: () async {}).update();
      expect(cache.get('page'), isNull);
      cache.put('page', [2], {}, status: 200);
      await expectLater(
        OtaUpdateManager(
          updateInstaller: () async {
            throw StateError('failed');
          },
        ).update(),
        throwsStateError,
      );
      expect(cache.get('page')!.bytes, [2]);
    },
  );

  test('keeps identical bytes and headers, then purges every instance', () {
    final a = DVRenderedPageCache();
    final b = DVRenderedPageCache();
    final bytes = utf8.encode('héllo');
    a.put('a', bytes, {'content-type': 'text/html'}, status: 200);
    b.put('b', bytes, {}, status: 200);
    expect(a.get('a')!.bytes, bytes);
    expect(a.get('a')!.headers['content-type'], 'text/html');
    dvPurgeRenderedPages();
    expect(a.get('a'), isNull);
    expect(b.get('b'), isNull);
  });
  test('Set-Cookie and non-200 cannot enter the cache', () {
    final cache = DVRenderedPageCache();
    cache.put('cookie', [1], {'Set-Cookie': 'session=private'}, status: 200);
    cache.put('error', [2], {}, status: 404);
    expect(cache.get('cookie'), isNull);
    expect(cache.get('error'), isNull);
  });
  test('bounded LRU evicts old entries', () {
    final cache = DVRenderedPageCache(maxBytes: 3, maxEntries: 2);
    cache.put('a', [1], {}, status: 200);
    cache.put('b', [2], {}, status: 200);
    cache.get('a');
    cache.put('c', [3], {}, status: 200);
    expect(cache.get('b'), isNull);
    expect(cache.get('a'), isNotNull);
    cache.put('large', [1, 2, 3, 4], {}, status: 200);
    expect(cache.get('large'), isNull);
  });
}
