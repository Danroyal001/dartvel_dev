// The address a request's connection came from, as a value.
//
// Every per-source limit compares these, so the failures worth a test are the
// ones that compare unequal while meaning the same host -- an IPv4 client on a
// dual-stack socket arrives as ::ffff:a.b.c.d, and the same IPv6 address can
// be written a dozen ways -- and the ones that parse something that is not an
// address into one that is.
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

void main() {
  group('DVIpAddress', () {
    test('an IPv4-mapped IPv6 address is the IPv4 address it maps', () {
      final DVIpAddress mapped = DVIpAddress.parse('::ffff:203.0.113.7');
      final DVIpAddress plain = DVIpAddress.parse('203.0.113.7');
      expect(mapped, plain);
      expect(mapped.hashCode, plain.hashCode);
      expect(mapped.isIPv4, isTrue);
      expect(mapped.toString(), '203.0.113.7');
      expect(DVIpAddress.parse('::FFFF:cb00:7107'), plain);
    });

    test('spellings of one IPv6 address are equal and print one way', () {
      final DVIpAddress a = DVIpAddress.parse('2001:0DB8:0000:0000:0000:0000:0000:0001');
      final DVIpAddress b = DVIpAddress.parse('2001:db8::1');
      expect(a, b);
      expect(a.toString(), '2001:db8::1');
      // RFC 5952: the longest run of zero groups is the one compressed, and a
      // single zero group is not compressed at all.
      expect(DVIpAddress.parse('2001:db8:0:0:1:0:0:0').toString(), '2001:db8:0:0:1::');
      expect(DVIpAddress.parse('2001:db8:0:1:1:1:1:1').toString(), '2001:db8:0:1:1:1:1:1');
      expect(DVIpAddress.parse('::').toString(), '::');
      expect(DVIpAddress.parse('::1').toString(), '::1');
    });

    test('IPv4 and a different IPv6 address are not equal', () {
      expect(DVIpAddress.parse('127.0.0.1'), isNot(DVIpAddress.parse('::1')));
      // IPv4-compatible (deprecated) is not IPv4-mapped.
      expect(DVIpAddress.parse('::127.0.0.1').isIPv4, isFalse);
    });

    test('what is not an address is not parsed into one', () {
      for (final String text in <String>[
        '',
        ' ',
        'unknown',
        '_hidden',
        '1.2.3',
        '1.2.3.4.5',
        '256.1.1.1',
        '01.2.3.4',
        '1.2.3.-4',
        '1.2.3.4 ',
        '1.2.3.4:80',
        '[::1]',
        '::1%eth0',
        '2001:db8::1::2',
        '12345::',
        'example.com',
        '1.2.3.4, 5.6.7.8',
      ]) {
        expect(DVIpAddress.tryParse(text), isNull, reason: '"$text"');
      }
      expect(() => DVIpAddress.parse('nope'), throwsFormatException);
    });
  });

  group('DVPeerAddress', () {
    test('reads the forms a socket address is written in', () {
      final DVPeerAddress v4 = DVPeerAddress.parse('198.51.100.4:51000');
      expect(v4.address, DVIpAddress.parse('198.51.100.4'));
      expect(v4.port, 51000);
      expect(v4.toString(), '198.51.100.4:51000');

      final DVPeerAddress v6 = DVPeerAddress.parse('[2001:db8::7]:443');
      expect(v6.address, DVIpAddress.parse('2001:db8::7'));
      expect(v6.port, 443);
      expect(v6.toString(), '[2001:db8::7]:443');

      // The port is optional in every form.
      expect(DVPeerAddress.parse('198.51.100.4').port, isNull);
      expect(DVPeerAddress.parse('[2001:db8::7]').port, isNull);
      expect(DVPeerAddress.parse('2001:db8::7').port, isNull);
      expect(DVPeerAddress.parse('2001:db8::7').toString(), '2001:db8::7');

      // A dual-stack socket's IPv4 client, with the scope id a link-local
      // peer carries: the host is the IPv4 address, the scope is dropped.
      expect(DVPeerAddress.parse('[::ffff:198.51.100.4]:9').address,
          DVIpAddress.parse('198.51.100.4'));
      expect(DVPeerAddress.parse('[fe80::1%2]:9').address,
          DVIpAddress.parse('fe80::1'));
    });

    test('refuses a port that is not a port and a host that is not an address',
        () {
      for (final String text in <String>[
        '198.51.100.4:',
        '198.51.100.4:65536',
        '198.51.100.4:-1',
        '198.51.100.4:http',
        '[2001:db8::7]:',
        '[2001:db8::7',
        'localhost:80',
        'for=198.51.100.4',
        '',
      ]) {
        expect(DVPeerAddress.tryParse(text), isNull, reason: '"$text"');
      }
    });
  });

  test('a request carries the peer it is given and none otherwise', () {
    final Request bare = Request(
      method: 'GET',
      url: Uri.parse('http://example.test/'),
      headers: Headers(<String, String>{'x-forwarded-for': '203.0.113.9'}),
      bodyStream: const Stream<List<int>>.empty(),
    );
    expect(bare.peerAddress, isNull,
        reason: 'a header is not a peer address');

    final Request connected = Request(
      method: 'GET',
      url: Uri.parse('http://example.test/'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
      peerAddress: DVPeerAddress.parse('198.51.100.4:51000'),
    );
    expect(connected.peerAddress?.address.toString(), '198.51.100.4');
  });
}
