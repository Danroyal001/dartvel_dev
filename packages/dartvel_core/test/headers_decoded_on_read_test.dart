// A server builds a request's headers from the bytes the connection carried,
// and many handlers never read one (a plain-text or JSON route, a static
// file). Headers.decodedOnRead decodes them the first time anything reads or
// changes them, once, and otherwise behaves as headers built whole.
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

void main() {
  test('nothing is decoded until the headers are read', () {
    var decoded = 0;
    final Headers headers = Headers.decodedOnRead(() {
      decoded++;
      return <String, List<String>>{
        'accept': <String>['text/html'],
        'cookie': <String>['a=1', 'b=2'],
      };
    });
    expect(decoded, 0);
    expect(headers.get('Accept'), 'text/html');
    expect(headers.getAll('cookie'), <String>['a=1', 'b=2']);
    expect(headers.has('x-missing'), isFalse);
    expect(decoded, 1, reason: 'decoded once, on the first read');
  });

  test('a change before any read lands on the decoded headers', () {
    final Headers headers = Headers.decodedOnRead(() => <String, List<String>>{
          'host': <String>['example.com'],
        });
    headers.set('X-Added', 'yes');
    headers.append('host', 'second');
    expect(headers.singleValueMap,
        <String, String>{'host': 'example.com', 'x-added': 'yes'});
    expect(headers.getAll('host'), <String>['example.com', 'second']);
    headers.delete('host');
    expect(headers.multiValueMap.keys, <String>['x-added']);
  });
}
