// What `dartvel dev` prints for Dartvel Preview: one link carrying both ways
// the app can run this project, and nothing when it can run it neither way.
import 'dart:typed_data';

import 'package:dartvel_cli/src/devclient/dev_preview_link.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Uri pairingLink() => DVDevClientPairing(
      server: Uri.parse('https://192.168.1.20:8787'),
      branch: 'main',
      publicKey: Uint8List.fromList(<int>[
        0x04,
        0x6b, 0x17, 0xd1, 0xf2, 0xe1, 0x2c, 0x42, 0x47, 0xf8, 0xbc, 0xe6, 0xe5,
        0x63, 0xa4, 0x40, 0xf2, 0x77, 0x03, 0x7d, 0x81, 0x2d, 0xeb, 0x33, 0xa0,
        0xf4, 0xa1, 0x39, 0x45, 0xd8, 0x98, 0xc2, 0x96,
        0x4f, 0xe3, 0x42, 0xe2, 0xfe, 0x1a, 0x7f, 0x9b, 0x8e, 0xe7, 0xeb, 0x4a,
        0x7c, 0x0f, 0x9e, 0x16, 0x2b, 0xce, 0x33, 0x57, 0x6b, 0x31, 0x5e, 0xce,
        0xcb, 0xb6, 0x40, 0x68, 0x37, 0xbf, 0x51, 0xf5,
      ]),
      token: dvWebPushBase64Encode(List<int>.filled(32, 7)),
    ).link;

void main() {
  test('the link carries the pairing and the web build, and Preview reads it',
      () {
    final DVPreviewAppLink? link = dvDevPreviewLink(
      name: 'shop',
      pairing: pairingLink(),
      web: Uri.parse('http://192.168.1.20:5000'),
    );
    final DVPreviewAppLink read = DVPreviewAppLink.parse(link.toString());
    expect(read.name, 'shop');
    expect(read.canRunCode, isTrue);
    expect(read.web, Uri.parse('http://192.168.1.20:5000'));
  });

  test('with only pairing, the link still runs the code', () {
    final DVPreviewAppLink? link =
        dvDevPreviewLink(name: 'shop', pairing: pairingLink(), web: null);
    expect(link?.canRunCode, isTrue);
    expect(link?.canOpenWeb, isFalse);
  });

  test('a web build only on this machine is not put in the link', () {
    // localhost on a phone is the phone.
    final DVPreviewAppLink? link = dvDevPreviewLink(
        name: 'shop',
        pairing: null,
        web: Uri.parse('http://localhost:5000'));
    expect(link, isNull);
  });

  test('with neither, there is nothing to print', () {
    expect(dvDevPreviewLink(name: 'shop', pairing: null, web: null), isNull);
  });
}
