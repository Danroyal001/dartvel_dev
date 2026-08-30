// The binary envelope encoding for backend transport.
//
// A codec fails in the worst way available: a decoder that reads a truncated
// or hostile buffer without complaining returns a plausible value, and the
// wrong data flows on as if it were right. Most of what follows is about
// refusing bad input rather than about round-tripping good input.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartvel_core/src/http/flat_buffer.dart';
import 'package:test/test.dart';

Object? roundTrip(Object? value) => dvFlatDecode(dvFlatEncode(value));

void main() {
  group('scalars round-trip', () {
    test('null', () => expect(roundTrip(null), isNull));
    test('true', () => expect(roundTrip(true), isTrue));
    test('zero', () => expect(roundTrip(0), 0));
    test('a negative int', () => expect(roundTrip(-42), -42));

    test('an int at the 64-bit boundary', () {
      // A length or tag written as 32 bits silently truncates here.
      expect(roundTrip(9223372036854775807), 9223372036854775807);
      expect(roundTrip(-9223372036854775808), -9223372036854775808);
    });

    test('a double keeps its exact bits', () {
      expect(roundTrip(0.1), 0.1);
      expect((roundTrip(-0.0) as double).isNegative, isTrue);
    });

    test('NaN and the infinities survive', () {
      // Encoding a double through its string form loses these.
      expect((roundTrip(double.nan) as double).isNaN, isTrue);
      expect(roundTrip(double.infinity), double.infinity);
      expect(roundTrip(double.negativeInfinity), double.negativeInfinity);
    });

    test('an int stays an int and a double stays a double', () {
      // 1 and 1.0 compare equal in Dart, so a codec that conflates them
      // passes a careless test and breaks a typed parameter.
      expect(roundTrip(1), isA<int>());
      expect(roundTrip(1.0), isA<double>());
    });
  });

  group('strings and bytes', () {
    test('empty is not null', () {
      expect(roundTrip(''), '');
      expect(roundTrip(''), isNot(isNull));
    });

    test('a multi-byte character is measured in bytes, not code units', () {
      // Writing a UTF-16 length and reading UTF-8 bytes truncates here.
      const String accented = 'héllo wörld';
      const String japanese = '日本語';
      expect(roundTrip(accented), accented);
      expect(roundTrip(japanese), japanese);
    });

    test('a character outside the basic plane survives', () {
      const String astral = 'a\u{1f469}b';
      expect(roundTrip(astral), astral);
    });

    test('a NUL inside a string is not a terminator', () {
      const String withNul = 'a\u0000b';
      expect(roundTrip(withNul), withNul);
      expect((roundTrip(withNul)! as String).length, 3);
    });

    test('bytes come back as bytes, not as a string', () {
      final Uint8List bytes = Uint8List.fromList(<int>[0, 255, 127, 128]);
      final Object? decoded = roundTrip(bytes);
      expect(decoded, isA<Uint8List>());
      expect(decoded, bytes);
    });

    test('empty bytes are distinct from an empty string', () {
      expect(roundTrip(Uint8List(0)), isA<Uint8List>());
      expect(roundTrip(''), isA<String>());
    });
  });

  group('collections', () {
    test('an empty list and an empty map are distinct', () {
      expect(roundTrip(<Object?>[]), isA<List<Object?>>());
      expect(roundTrip(<String, Object?>{}), isA<Map<String, Object?>>());
    });

    test('nesting survives', () {
      final Object? value = <String, Object?>{
        'a': <Object?>[1, 'two', 3.0, null, true],
        'b': <String, Object?>{
          'c': <String, Object?>{'d': <Object?>[]},
        },
      };
      expect(roundTrip(value), value);
    });

    test('key order is preserved, so a signature over bytes is stable', () {
      final Map<String, Object?> value = <String, Object?>{
        'z': 1,
        'a': 2,
        'm': 3,
      };
      expect((roundTrip(value)! as Map<String, Object?>).keys.toList(),
          <String>['z', 'a', 'm']);
    });

    test('two encodings of the same value are byte-identical', () {
      final Map<String, Object?> value =
          <String, Object?>{'a': 1, 'b': <int>[1, 2]};
      expect(dvFlatEncode(value), dvFlatEncode(value));
    });
  });

  group('refusing bad input', () {
    test('an empty buffer is refused', () {
      expect(() => dvFlatDecode(Uint8List(0)), throwsFormatException);
    });

    test('a wrong magic is refused', () {
      final Uint8List bad = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(() => dvFlatDecode(bad), throwsFormatException);
    });

    test('a truncated buffer is refused rather than half-decoded', () {
      final Uint8List whole = dvFlatEncode(<String, Object?>{
        'name': 'Ada Lovelace',
        'roles': <String>['admin', 'engineer'],
      });
      for (int cut = 1; cut < whole.length; cut += 1) {
        expect(
          () => dvFlatDecode(Uint8List.sublistView(whole, 0, cut)),
          throwsFormatException,
          reason: 'truncating to $cut bytes must not decode',
        );
      }
    });

    test('a length claiming more than the buffer holds is refused', () {
      // The classic hostile-input case: an attacker-controlled length that
      // would read past the end.
      final Uint8List whole = dvFlatEncode('hello');
      final Uint8List tampered = Uint8List.fromList(whole);
      tampered[dvFlatHeaderLength + 1] = 0xFF;
      expect(() => dvFlatDecode(tampered), throwsFormatException);
    });

    test('trailing bytes are refused, not ignored', () {
      // Silently ignoring them lets two different buffers decode alike,
      // which is how a signature check gets bypassed.
      final Uint8List whole = dvFlatEncode(42);
      final Uint8List extra = Uint8List.fromList(<int>[...whole, 0, 0, 0]);
      expect(() => dvFlatDecode(extra), throwsFormatException);
    });

    test('an unknown type tag is refused', () {
      final Uint8List whole = dvFlatEncode(42);
      final Uint8List tampered = Uint8List.fromList(whole);
      tampered[dvFlatHeaderLength] = 0x7E;
      expect(() => dvFlatDecode(tampered), throwsFormatException);
    });

    test('an unsupported value is refused at encode time', () {
      expect(() => dvFlatEncode(DateTime.now()), throwsArgumentError);
    });
  });

  test('the buffer names the encoding, so a reader knows what it has', () {
    final Uint8List whole = dvFlatEncode(null);
    expect(whole.length, greaterThanOrEqualTo(dvFlatHeaderLength));
    expect(utf8.decode(whole.sublist(0, 4)), 'DVFB');
  });
}
