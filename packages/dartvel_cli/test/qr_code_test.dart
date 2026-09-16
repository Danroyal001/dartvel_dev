// The QR code `dartvel dev` prints for a phone to scan.
//
// A QR code that looks right and does not scan is the silent failure here, so
// the reference is not this encoder's own output. fixtures/qr_reference.json
// was written by an independent encoder -- the `qrcode` npm package, byte mode,
// with the mask forced so the choice of mask cannot hide a difference -- and
// each matrix was decoded back to its text with the `jsqr` decoder before it
// was committed. Matching it module for module is matching a code that scans.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/utils/qr_code.dart';
import 'package:test/test.dart';

DVQrErrorCorrection _level(String name) => switch (name) {
  'L' => DVQrErrorCorrection.low,
  'M' => DVQrErrorCorrection.medium,
  'Q' => DVQrErrorCorrection.quartile,
  _ => DVQrErrorCorrection.high,
};

List<String> _rows(DVQrCode code) => <String>[
  for (int y = 0; y < code.size; y++)
    <String>[
      for (int x = 0; x < code.size; x++) code.isDark(x, y) ? '1' : '0',
    ].join(),
];

void main() {
  final List<Object?> references =
      jsonDecode(File('test/fixtures/qr_reference.json').readAsStringSync())
          as List<Object?>;

  for (final Object? entry in references) {
    final Map<String, Object?> reference = entry! as Map<String, Object?>;
    final String text = reference['text']! as String;
    final int version = reference['version']! as int;
    test(
      'version $version, level ${reference['ecl']}, mask ${reference['mask']} '
      'matches the reference module for module',
      () {
        final DVQrCode code = DVQrCode.encodeText(
          text,
          errorCorrection: _level(reference['ecl']! as String),
          mask: reference['mask']! as int,
        );
        expect(code.version, version);
        expect(code.size, version * 4 + 17);
        expect(_rows(code), reference['rows']);
      },
    );
  }

  test('the smallest version that holds the data is chosen', () {
    expect(DVQrCode.encodeText('HELLO').version, 1);
    // Version 1 at level M holds 14 bytes in byte mode; 15 does not fit.
    expect(DVQrCode.encodeText('a' * 14).version, 1);
    expect(DVQrCode.encodeText('a' * 15).version, 2);
  });

  test('left to choose, the mask is the one with the lowest penalty', () {
    const String link = 'http://192.168.1.20:8080/';
    final DVQrCode chosen = DVQrCode.encodeText(link);
    final List<int> penalties = <int>[
      for (int mask = 0; mask < 8; mask++)
        DVQrCode.encodeText(link, mask: mask).penalty,
    ];
    expect(chosen.penalty, penalties.reduce((int a, int b) => a < b ? a : b));
    expect(chosen.mask, penalties.indexOf(chosen.penalty));
  });

  test('more than the largest code holds is refused, not truncated', () {
    expect(
      () => DVQrCode.encodeText('z' * 3000, errorCorrection: DVQrErrorCorrection.high),
      throwsA(isA<ArgumentError>()),
    );
  });

  group('in a terminal', () {
    final DVQrCode code = DVQrCode.encodeText('HELLO');

    test('two module rows per text line, with a quiet zone all round', () {
      final List<String> lines = dvQrTerminalLines(code, ansi: false);
      // 21 modules plus a 4-module quiet zone each side, halved and rounded up.
      expect(lines, hasLength((21 + 8 + 1) ~/ 2));
      for (final String line in lines) {
        expect(line.runes.length, 21 + 8);
      }
    });

    test('without colour, dark modules are the terminal background', () {
      // A plain terminal draws glyphs light on dark, so a light module is a
      // drawn block and a dark module is a space -- the way round a camera
      // reads as a QR code.
      final List<String> lines = dvQrTerminalLines(code, ansi: false);
      // The quiet zone is light: the first line is solid blocks.
      expect(lines.first, '█' * (21 + 8));
      // The finder's top-left corner is dark: row 4, column 4 of the padded
      // grid is the top half of the third line's fifth character.
      final String corner = String.fromCharCode(lines[2].runes.elementAt(4));
      expect(corner, anyOf(' ', '▄'));
    });

    test('with colour, it paints black on white whatever the theme', () {
      final String out = dvQrTerminalLines(code, ansi: true).join('\n');
      expect(out, contains('\x1b[30;47m'));
      expect(out, contains('\x1b[0m'));
    });
  });
}
