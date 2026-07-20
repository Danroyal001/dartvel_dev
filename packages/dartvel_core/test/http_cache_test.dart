import 'package:dartvel_core/src/http/cache.dart';
import 'package:test/test.dart';

void main() {
  test('HttpCache stores and retrieves values with explicit types', () {
    final cache = HttpCache.instance;
    cache.set<String>('greeting', 'hello');

    expect(cache.get<String>('greeting'), 'hello');
    expect(() => cache.get<int>('greeting'), throwsA(isA<TypeError>()));
  });

  test('HttpCache removes expired entries', () {
    final cache = HttpCache.instance;
    cache.set<String>('temporary', 'value', ttl: Duration.zero);

    expect(cache.get<String>('temporary'), isNull);
    expect(cache.has('temporary'), isFalse);
  });
}
