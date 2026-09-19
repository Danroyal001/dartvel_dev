// DV.Auth.code(): the code an application asks somebody to type back.
//
// Every project that mails a sign-in code was writing its own Random and
// padding, and a Random that is not Random.secure is a code somebody can
// predict. One helper, secure by construction, with the length as the only
// thing a caller usually changes.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('is six digits when nothing says otherwise', () {
    final String code = DV.Auth.code();

    expect(code, matches(RegExp(r'^\d{6}$')));
  });

  test('is as long as it is asked to be', () {
    expect(DV.Auth.code(length: 4), matches(RegExp(r'^\d{4}$')));
    expect(DV.Auth.code(length: 10), matches(RegExp(r'^\d{10}$')));
  });

  test('keeps its leading zeros', () {
    // A code built from a number loses them, and "012345" typed back as
    // 12345 fails to match for a reason nobody can see.
    final Iterable<String> many =
        Iterable<String>.generate(400, (_) => DV.Auth.code());

    expect(many.every((String c) => c.length == 6), isTrue);
    expect(many.any((String c) => c.startsWith('0')), isTrue);
  });

  test('is not the same code twice', () {
    final Set<String> codes = <String>{
      for (int i = 0; i < 200; i++) DV.Auth.code(),
    };

    expect(codes.length, greaterThan(150));
  });

  test('refuses a length nobody could type, or that anybody could guess', () {
    expect(() => DV.Auth.code(length: 3), throwsA(isA<ArgumentError>()));
    expect(() => DV.Auth.code(length: 0), throwsA(isA<ArgumentError>()));
    expect(() => DV.Auth.code(length: 33), throwsA(isA<ArgumentError>()));
  });
}
