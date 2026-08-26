// Strings handed to the Rust side, and the bytes they become.
//
// Every FfiStr the server passes is decoded with std::str::from_utf8 on the
// Rust side. Dart was building those byte lists from String.codeUnits, which
// is UTF-16, and the two agree only for ASCII.
//
// The failure has two shapes and the second is worse. A character in the
// Latin-1 range emits one byte that is not a valid UTF-8 sequence, and Rust
// rejects it -- an error, at least. A character above U+00FF emits a code unit
// larger than a byte, and Uint8List.fromList truncates it rather than
// throwing: `/srv/中文` becomes `/srv/--`, a path that does not exist, and
// static files simply stop being found with nothing logged anywhere.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_shelf/src/ffi_string.dart';
import 'package:dartvel_shelf/src/header_codec.dart';
import 'package:test/test.dart';

void main() {
  group('encoding a string for the Rust side', () {
    test('ASCII is unchanged, which is why this was never noticed', () {
      expect(dvFfiBytes('/srv/static'), utf8.encode('/srv/static'));
    });

    test('a Latin-1 character becomes its UTF-8 sequence, not one byte', () {
      final bytes = dvFfiBytes('café');

      expect(bytes, utf8.encode('café'));
      expect(bytes.length, 5, reason: 'é is two bytes in UTF-8');
      expect(utf8.decode(bytes), 'café');
    });

    test('a character above U+00FF is not truncated to a byte', () {
      // The silent one. '中' is U+4E2D; the low byte of that is 0x2D, which
      // is a hyphen.
      final bytes = dvFfiBytes('/srv/中文');

      expect(utf8.decode(bytes), '/srv/中文');
      expect(String.fromCharCodes(bytes), isNot(contains('--')));
    });

    test('an emoji survives, surrogate pair and all', () {
      // Outside the basic plane, so it is two code units in Dart and four
      // bytes in UTF-8. Anything working per code unit gets this wrong twice.
      final bytes = dvFfiBytes('ok 🎉');

      expect(utf8.decode(bytes), 'ok 🎉');
      expect(bytes.length, utf8.encode('ok 🎉').length);
    });

    test('an empty string is empty rather than null', () {
      expect(dvFfiBytes(''), isEmpty);
    });

    test('the result is a Uint8List, so every element is a real byte', () {
      final bytes = dvFfiBytes('中文');

      expect(bytes, isA<Uint8List>());
      expect(bytes.every((int b) => b >= 0 && b <= 255), isTrue);
    });
  });

  group('headers over the boundary', () {
    test('a header value round trips through the flat encoding', () {
      final encoded = encodeHeaders(<String, List<String>>{
        'content-type': <String>['text/plain'],
      });

      expect(decodeHeaders(encoded)['content-type'], <String>['text/plain']);
    });

    test('a non-ASCII header value survives the round trip', () {
      // Filenames reach content-disposition, and they are not all ASCII.
      final encoded = encodeHeaders(<String, List<String>>{
        'x-filename': <String>['rapport-financière.pdf'],
      });

      expect(decodeHeaders(encoded)['x-filename'],
          <String>['rapport-financière.pdf']);
    });

    test('repeated headers keep all their values', () {
      final encoded = encodeHeaders(<String, List<String>>{
        'set-cookie': <String>['a=1', 'b=2'],
      });

      expect(decodeHeaders(encoded)['set-cookie'], <String>['a=1', 'b=2']);
    });

    test('keys are lowercased on the way back, and values are not', () {
      final encoded = encodeHeaders(<String, List<String>>{
        'X-Trace-Id': <String>['AbC'],
      });

      expect(decodeHeaders(encoded).keys, contains('x-trace-id'));
      expect(decodeHeaders(encoded)['x-trace-id'], <String>['AbC']);
    });
  });
}
