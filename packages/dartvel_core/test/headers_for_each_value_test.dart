// A server writing a response's headers out visits each name and value in
// place, rather than through multiValueMap, which copies the whole map on
// every response.
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

void main() {
  test('every value of every header, in the order they were added', () {
    final Headers headers = Headers()
      ..set('Content-Type', 'text/plain')
      ..append('Set-Cookie', 'a=1')
      ..append('set-cookie', 'b=2')
      ..set('X-Empty', '');
    final List<String> seen = <String>[];
    headers.forEachValue((String name, String value) => seen.add('$name=$value'));
    expect(seen, <String>[
      'content-type=text/plain',
      'set-cookie=a=1',
      'set-cookie=b=2',
      'x-empty=',
    ]);
  });

  test('headers decoded on read are decoded for it', () {
    final Headers headers = Headers.decodedOnRead(() => <String, List<String>>{
          'accept': <String>['*/*'],
        });
    final List<String> seen = <String>[];
    headers.forEachValue((String name, String value) => seen.add('$name=$value'));
    expect(seen, <String>['accept=*/*']);
  });
}
