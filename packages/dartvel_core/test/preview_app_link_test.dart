// The link `dartvel dev` prints for Dartvel Preview, and what the app does
// with one: run the project's code through the pairing it carries, or open
// its web build at the address it carries. Anything else is refused by
// name, because the app acts on what it is handed.
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVDevClientPairing pairing() => DVDevClientPairing(
      server: Uri.parse('https://192.168.1.20:8787'),
      branch: 'main',
      // An uncompressed P-256 point: 0x04, then 64 bytes. The generator
      // point, so it is on the curve.
      publicKey: Uint8List.fromList(<int>[
        0x04,
        0x6b, 0x17, 0xd1, 0xf2, 0xe1, 0x2c, 0x42, 0x47, 0xf8, 0xbc, 0xe6, 0xe5,
        0x63, 0xa4, 0x40, 0xf2, 0x77, 0x03, 0x7d, 0x81, 0x2d, 0xeb, 0x33, 0xa0,
        0xf4, 0xa1, 0x39, 0x45, 0xd8, 0x98, 0xc2, 0x96,
        0x4f, 0xe3, 0x42, 0xe2, 0xfe, 0x1a, 0x7f, 0x9b, 0x8e, 0xe7, 0xeb, 0x4a,
        0x7c, 0x0f, 0x9e, 0x16, 0x2b, 0xce, 0x33, 0x57, 0x6b, 0x31, 0x5e, 0xce,
        0xcb, 0xb6, 0x40, 0x68, 0x37, 0xbf, 0x51, 0xf5,
      ]),
      // 32 bytes, the least a pairing token may be.
      token: dvWebPushBase64Encode(List<int>.filled(32, 7)),
    );

void main() {
  test('a link carries the project, its pairing and its web address', () {
    final DVPreviewAppLink link = DVPreviewAppLink(
      name: 'shop',
      pairing: pairing().link,
      web: Uri.parse('http://192.168.1.20:5000'),
    );
    final Uri uri = link.toUri();
    expect(uri.scheme, 'dartvel-preview');
    expect(uri.host, 'open');

    final DVPreviewAppLink back = DVPreviewAppLink.parse(uri.toString());
    expect(back.name, 'shop');
    expect(back.pairing, pairing().link);
    expect(back.web, Uri.parse('http://192.168.1.20:5000'));
    expect(back.canRunCode, isTrue);
    expect(back.canOpenWeb, isTrue);
  });

  test('a bare pairing link and a bare web address are links too', () {
    // What the terminal already printed before Preview existed, pasted as is.
    final DVPreviewAppLink paired =
        DVPreviewAppLink.parse(pairing().link.toString());
    expect(paired.canRunCode, isTrue);
    expect(paired.canOpenWeb, isFalse);

    final DVPreviewAppLink web =
        DVPreviewAppLink.parse('  http://192.168.1.20:5000/  ');
    expect(web.canRunCode, isFalse);
    expect(web.web, Uri.parse('http://192.168.1.20:5000/'));
  });

  test('a web address that is not http or https is refused', () {
    // The web address is loaded into the app's frame. javascript:, file: and
    // data: would run or read something other than a dev server's page.
    for (final String bad in <String>[
      'javascript:alert(1)',
      'file:///etc/passwd',
      'data:text/html,<script>1</script>',
      'dartvel-preview://open?web=javascript%3Aalert(1)',
      'dartvel-preview://open?web=file%3A%2F%2F%2Fetc%2Fpasswd',
    ]) {
      expect(() => DVPreviewAppLink.parse(bad), throwsFormatException,
          reason: bad);
    }
  });

  test('a pairing it could not trust is refused, not carried', () {
    // The same checks the tunnel makes, made before the app acts on it: an
    // http server, or a link with no key, is never handed to the tunnel.
    final Uri http = pairing().link.replace(queryParameters: <String, String>{
      ...pairing().link.queryParameters,
      'server': 'http://192.168.1.20:8787',
    });
    expect(
        () => DVPreviewAppLink.parse(DVPreviewAppLink(pairing: http)
            .toUri()
            .toString()),
        throwsFormatException);
    expect(() => DVPreviewAppLink.parse('dartvel-dev://pair?server=https%3A%2F%2Fx'),
        throwsFormatException);
  });

  test('a link with nothing to open is refused', () {
    expect(() => DVPreviewAppLink.parse('dartvel-preview://open?name=shop'),
        throwsFormatException);
    expect(() => DVPreviewAppLink.parse(''), throwsFormatException);
    expect(() => DVPreviewAppLink.parse('hello'), throwsFormatException);
  });
}
