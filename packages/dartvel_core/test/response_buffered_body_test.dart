// A body that is already in memory says so, so a server can send it as one
// copy instead of listening to a stream for a piece it already holds.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/src/http/wintercg.dart';
import 'package:test/test.dart';

void main() {
  test('Response.text and Response.json carry their bytes whole', () async {
    final text = Response.text('héllo');
    expect(text.bufferedBytes, utf8.encode('héllo'));
    expect(await text.body!.text(), 'héllo',
        reason: 'the stream still reads the same body');

    final json = Response.json({'a': 1});
    expect(utf8.decode(json.bufferedBytes!), '{"a":1}');
    expect(await json.body!.jsonDecode(), {'a': 1});
  });

  test('Response.bytes keeps the body and the headers it was given', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final response = Response.bytes(201, bytes,
        headers: Headers({'content-type': 'application/octet-stream'}));
    expect(response.status, 201);
    expect(response.bufferedBytes, same(bytes));
    expect(response.headers.get('content-type'), 'application/octet-stream');
    expect(await response.body!.bytesU8(), [1, 2, 3]);
  });

  test('a streamed or empty body has no buffered bytes', () {
    expect(Response(200, body: Stream.value([1])).bufferedBytes, isNull);
    expect(Response(204).bufferedBytes, isNull);
    expect(Response(204).body, isNull);
  });
}
