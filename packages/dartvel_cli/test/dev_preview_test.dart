// What `dartvel dev` prints so a phone can open the app: the address on the
// LAN, and a QR code of it.
import 'dart:io';

import 'package:dartvel_cli/src/utils/lan_address.dart';
import 'package:dartvel_cli/src/utils/qr_code.dart';
import 'package:test/test.dart';

DVNamedAddress at(String interface, String address) =>
    DVNamedAddress(interface, InternetAddress(address));

void main() {
  group('the LAN address a phone is told to use', () {
    test('Wi-Fi over a Docker bridge listed first', () {
      // docker0 is a private address on every Linux machine with Docker, and
      // it is listed before the Wi-Fi. A phone cannot reach it.
      expect(
        dvLanHost(<DVNamedAddress>[
          at('lo', '127.0.0.1'),
          at('docker0', '172.17.0.1'),
          at('br-4f2a', '172.18.0.1'),
          at('wlan0', '192.168.1.20'),
        ]),
        '192.168.1.20',
      );
    });

    test('virtual machine and VPN interfaces are passed over too', () {
      expect(
        dvLanHost(<DVNamedAddress>[
          at('vboxnet0', '192.168.56.1'),
          at('vmnet8', '192.168.200.1'),
          at('virbr0', '192.168.122.1'),
          at('bridge100', '192.168.64.1'),
          at('utun3', '10.8.0.2'),
          at('en0', '10.0.0.7'),
        ]),
        '10.0.0.7',
      );
    });

    test('a private address over a public or link-local one', () {
      expect(
        dvLanHost(<DVNamedAddress>[
          at('eth1', '169.254.3.4'),
          at('eth2', '203.0.113.9'),
          at('eth0', '192.168.1.20'),
        ]),
        '192.168.1.20',
      );
    });

    test('a virtual interface when it is all there is, before loopback', () {
      expect(
        dvLanHost(<DVNamedAddress>[
          at('lo', '127.0.0.1'),
          at('docker0', '172.17.0.1'),
        ]),
        '172.17.0.1',
      );
    });

    test('loopback only when there is nothing else', () {
      expect(dvLanHost(<DVNamedAddress>[at('lo', '127.0.0.1')]), '127.0.0.1');
    });
  });

  group('the preview URL', () {
    test('a server bound to every interface is announced at the LAN host', () {
      expect(
        dvLanPreviewUrl(bindHost: '0.0.0.0', port: 8080, lanHost: '10.0.0.7'),
        Uri.parse('http://10.0.0.7:8080'),
      );
    });

    test('a server bound to one LAN address is announced there', () {
      expect(
        dvLanPreviewUrl(
          bindHost: '192.168.1.20',
          port: 8080,
          lanHost: '10.0.0.7',
        ),
        Uri.parse('http://192.168.1.20:8080'),
      );
    });

    test('a server bound to loopback has no address a phone can use', () {
      for (final String host in <String>['localhost', '127.0.0.1', '::1']) {
        expect(
          dvLanPreviewUrl(bindHost: host, port: 8080, lanHost: '10.0.0.7'),
          isNull,
        );
      }
    });

    test('nor does one when the machine has no LAN address', () {
      expect(
        dvLanPreviewUrl(bindHost: '0.0.0.0', port: 8080, lanHost: '127.0.0.1'),
        isNull,
      );
    });
  });

  test('the printed block carries the link and a QR code of exactly it', () {
    const String link = 'http://10.0.0.7:8080';
    final List<String> lines = dvQrBlock(
      heading: 'Open on your phone',
      link: link,
      ansi: false,
    );
    expect(lines.first, contains('Open on your phone'));
    expect(lines.last.trim(), link);
    final List<String> expected = dvQrTerminalLines(
      DVQrCode.encodeText(link),
      ansi: false,
    );
    expect(lines, containsAllInOrder(expected));
  });
}
