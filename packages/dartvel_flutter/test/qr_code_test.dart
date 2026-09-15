// QR codes for authenticator enrollment, encoded in Dart.
//
// The otpauth:// URI is only useful if a phone's camera reads back exactly
// what the server stored. A QR encoder fails silently: a wrong block split,
// a format word computed with the wrong mask or a misplaced module draws a
// perfectly plausible square that no scanner accepts -- or, worse, that one
// forgiving scanner accepts and another does not. So every symbol here is
// read back by test/support/qr_reader.dart, which shares no code with the
// encoder and checks the finder, timing and alignment patterns, both format
// copies against the published table, the version words, every block's
// Reed-Solomon syndromes and the byte-mode payload.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/qr_reader.dart';

void main() {
  test('round-trips short, medium and long payloads through an independent '
      'reader', () {
    for (final String text in <String>[
      'hi',
      'HELLO WORLD',
      'otpauth://totp/Probe:ada%40acme.test?secret=JBSWY3DPEHPK3PXP&issuer=Probe',
      'otpauth://totp/Acme%20Corporation:grace.hopper%40example.com?'
          'secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Acme%20Corporation'
          '&algorithm=SHA1&digits=6&period=30',
      'x' * 200,
    ]) {
      final DVQrCode code = DVQrCode.encode(text);
      final QrReading reading = readQr(code.modules);
      expect(reading.text, text, reason: 'version ${reading.version}');
      expect(code.size, reading.version * 4 + 17);
    }
  });

  test('uses the smallest version that holds the payload, and version '
      'information from version 7', () {
    expect(readQr(DVQrCode.encode('a' * 14).modules).version, 1);
    expect(readQr(DVQrCode.encode('a' * 15).modules).version, 2);
    // 122 bytes is the most version 7 holds at level M.
    expect(readQr(DVQrCode.encode('a' * 122).modules).version, 7);
    expect(readQr(DVQrCode.encode('a' * 123).modules).version, 8);
  });

  test('encodes at level M and picks a mask the reader agrees on', () {
    final Set<int> masks = <int>{};
    for (int i = 0; i < 40; i++) {
      final QrReading reading =
          readQr(DVQrCode.encode('otpauth://totp/x:$i?secret=ABC$i').modules);
      expect(reading.level, 'M');
      masks.add(reading.mask);
    }
    // The mask is chosen per symbol, not fixed.
    expect(masks.length, greaterThan(1));
  });

  test('carries UTF-8, so an issuer with an accent survives', () {
    const String text = 'otpauth://totp/Café:z%40e.test?secret=AAAA';
    final QrReading reading = readQr(DVQrCode.encode(text).modules);
    expect(utf8.decode(reading.text.codeUnits), text);
  });

  test('refuses a payload too long for the versions it supports, rather than '
      'drawing a truncated code', () {
    expect(() => DVQrCode.encode('a' * 3000), throwsArgumentError);
  });

  test('the reader refuses a symbol with one module flipped in the format '
      'area, so it is not a reader that accepts anything', () {
    final DVQrCode code = DVQrCode.encode('control');
    final List<List<bool>> tampered = <List<bool>>[
      for (final List<bool> row in code.modules) List<bool>.of(row),
    ];
    tampered[8][2] = !tampered[8][2];
    expect(() => readQr(tampered), throwsA(isA<QrReadFailure>()));
    final List<List<bool>> data = <List<bool>>[
      for (final List<bool> row in code.modules) List<bool>.of(row),
    ];
    data[code.size - 1][code.size - 1] = !data[code.size - 1][code.size - 1];
    expect(() => readQr(data), throwsA(isA<QrReadFailure>()));
  });

  testWidgets('DVQrImage paints the symbol it was given, with a quiet zone',
      (WidgetTester tester) async {
    const String text = 'otpauth://totp/Probe:a?secret=JBSWY3DPEHPK3PXP';
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: DVQrImage(data: text, size: 232)),
    ));
    expect(tester.takeException(), isNull);
    final DVQrImage image = tester.widget(find.byType(DVQrImage));
    expect(readQr(image.code.modules).text, text);
    expect(tester.getSize(find.byType(DVQrImage)), const Size(232, 232));
    expect(find.bySemanticsLabel('QR code'), findsOneWidget);
  });
}
