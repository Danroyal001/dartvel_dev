// Response.json writes its UTF-8 straight from the value, without building
// the JSON text first. These pin that the bytes, the headers and the errors
// are exactly what utf8.encode(jsonEncode(value)) gave.
import 'dart:convert';

import 'package:dartvel_core/src/http/wintercg.dart';
import 'package:test/test.dart';

class _WithToJson {
  Map<String, Object?> toJson() => {'kind': 'custom', 'n': 3};
}

class _NoToJson {}

void main() {
  final values = <String, Object?>{
    'small map': {'message': 'Hello, World!'},
    'null': null,
    'numbers': [0, -1, 1.5, 1e300, 9007199254740993],
    'escapes': 'quote " backslash \\ newline \n tab \t nul \u0000 del \u007f',
    'non-ASCII': 'héllo wörld ñ 中文',
    'astral': 'emoji \u{1F600} and \u{10FFFF}',
    'lone surrogates': 'high \uD800 low \uDC00 reversed \uDC00\uD800 end',
    'nested': {
      'list': [
        {'a': true, 'b': false},
        [],
        {},
      ],
      'deep': {
        'x': {
          'y': {'z': 'é'},
        },
      },
    },
    'toJson': [_WithToJson(), _WithToJson()],
    // Past any internal buffer, so the output is put together from pieces.
    'large': [for (var i = 0; i < 5000; i++) 'item $i é \u{1F600}'],
  };

  for (final MapEntry<String, Object?> entry in values.entries) {
    test('the same bytes as jsonEncode then utf8.encode: ${entry.key}', () {
      final response = Response.json(entry.value);
      expect(response.bufferedBytes, utf8.encode(jsonEncode(entry.value)));
      expect(
        response.headers.get('content-type'),
        'application/json; charset=utf-8',
      );
    });
  }

  test('a value JSON cannot hold fails as jsonEncode does', () {
    expect(
      () => Response.json({'bad': _NoToJson()}),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(
      () => Response.json(double.nan),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(() => Response.json(cycle), throwsA(isA<JsonCyclicError>()));
  });

  test('a content type the caller set is kept, and the status', () {
    final response = Response.json(
      [1],
      status: 201,
      headers: Headers({'content-type': 'application/problem+json'}),
    );
    expect(response.status, 201);
    expect(response.headers.get('content-type'), 'application/problem+json');
    expect(response.bufferedBytes, utf8.encode('[1]'));
  });

  test('the body is exactly as long as the JSON', () {
    final response = Response.json({'message': 'Hello, World!'});
    expect(response.bufferedBytes!.length, 27);
    expect(response.bufferedBytes!.lengthInBytes, 27);
  });
}
