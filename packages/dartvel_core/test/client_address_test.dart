// Who a request came from, for everything that counts per source.
//
// The failures here are all silent. Each one still produces an address, and
// every limit keyed on it goes on counting -- just not the client:
//  * a spoofed X-Forwarded-For from a peer nobody trusts changing the source;
//  * the trusted proxy's own address counted as the client, so every client
//    behind it shares one bucket;
//  * an entry an attacker put to the left of the real client being chosen;
//  * ::ffff:a.b.c.d comparing unequal to a.b.c.d in the trusted list or as a
//    source;
//  * a request with no peer address falling back to a header.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(String? peer, [Map<String, Object> headers = const {}]) {
  final Headers h = Headers();
  headers.forEach((String name, Object value) {
    if (value is List<String>) {
      for (final String v in value) {
        h.append(name, v);
      }
    } else {
      h.set(name, '$value');
    }
  });
  return Request(
    method: 'POST',
    url: Uri.parse('http://app.test/auth/sign-in'),
    headers: h,
    bodyStream: const Stream<List<int>>.empty(),
    peerAddress: peer == null ? null : DVPeerAddress.parse(peer),
  );
}

void main() {
  final DVClientAddress behindCaddy =
      DVClientAddress.parse(const <String>['127.0.0.1/32', '::1/128']);

  // A per-source limit counts sources, and an IPv6 source is a network, not
  // an address. A subscriber is routinely given a /64 and chooses any of its
  // 2^64 addresses per connection, so a limit keyed on the address counts
  // one client as a new source per request -- and still looks like it works.
  group('per-source buckets', () {
    tearDown(DVClientAddress.reset);

    String sourceOf(String peer, [DVClientAddress? resolver]) {
      if (resolver != null) DVClientAddress.install(resolver);
      return DVClientAddress.sourceOf(_request(peer));
    }

    test('addresses in one /64 are one source by default', () {
      final String first = sourceOf('[2001:db8:1:2::1]:5000');
      expect(sourceOf('[2001:db8:1:2:ffff:ffff:ffff:fffe]:5001'), first);
      expect(sourceOf('[2001:db8:1:2:abcd::9]:5002'), first);
      expect(first, '2001:db8:1:2::/64');
    });

    test('the next /64 is another source', () {
      expect(sourceOf('[2001:db8:1:3::1]:1'),
          isNot(sourceOf('[2001:db8:1:2::1]:1')));
    });

    test('IPv4 is counted per address', () {
      expect(sourceOf('203.0.113.7:1'), '203.0.113.7');
      expect(sourceOf('203.0.113.8:1'), isNot(sourceOf('203.0.113.7:1')));
    });

    test('an IPv4-mapped peer is its IPv4 address, not a member of ::/64',
        () {
      // Bucketed as IPv6 it would share ::ffff:0:0/64 with every IPv4 client
      // of a dual-stack socket: all of them one source.
      expect(sourceOf('[::ffff:203.0.113.7]:1'), '203.0.113.7');
      expect(sourceOf('[::ffff:203.0.113.8]:1'),
          isNot(sourceOf('[::ffff:203.0.113.7]:1')));
    });

    test('the client a trusted proxy reports is bucketed the same way', () {
      DVClientAddress.install(behindCaddy);
      String via(String client) => DVClientAddress.sourceOf(_request(
          '127.0.0.1:9', <String, Object>{'x-forwarded-for': client}));
      expect(via('2001:db8:9:9::1'), via('2001:db8:9:9::2'));
      expect(via('2001:db8:9:9::1'), '2001:db8:9:9::/64');
    });

    test('the prefix is configurable', () {
      const DVClientAddress wide = DVClientAddress(ipv6SourcePrefix: 56);
      expect(sourceOf('[2001:db8:1:2ff::1]:1', wide),
          sourceOf('[2001:db8:1:200::1]:1', wide));
      expect(sourceOf('[2001:db8:1:200::1]:1', wide), '2001:db8:1:200::/56');

      const DVClientAddress exact = DVClientAddress(ipv6SourcePrefix: 128);
      expect(sourceOf('[2001:db8::1]:1', exact), '2001:db8::1');
      expect(sourceOf('[2001:db8::2]:1', exact),
          isNot(sourceOf('[2001:db8::1]:1', exact)));
    });

    test('configuration carries the prefix', () {
      final DVClientAddress resolver =
          DVClientAddress.fromConfiguration(ipv6SourcePrefix: 48);
      expect(resolver.ipv6SourcePrefix, 48);
      expect(const DVClientAddress().ipv6SourcePrefix, 64);
    });

    test('a prefix outside 32 to 128 is refused', () {
      for (final int bad in <int>[0, 31, 129, -64]) {
        expect(() => DVClientAddress.checkIpv6SourcePrefix(bad),
            throwsFormatException, reason: '$bad');
        expect(() => DVClientAddress.fromConfiguration(ipv6SourcePrefix: bad),
            throwsFormatException, reason: '$bad');
      }
      for (final int good in <int>[32, 48, 64, 128]) {
        expect(DVClientAddress.checkIpv6SourcePrefix(good), good);
      }
    });

    test('the sign-in and sign-up source is the bucket', () {
      expect(
        DVAuthEndpoints.sourceOf(_request('[2001:db8:5:5::10]:1')),
        DVAuthEndpoints.sourceOf(_request('[2001:db8:5:5::11]:1')),
      );
    });
  });

  group('the peer decides unless it is a trusted proxy', () {
    test('a spoofed header from an untrusted peer changes nothing', () {
      const DVClientAddress none = DVClientAddress();
      for (final DVClientAddress resolver in <DVClientAddress>[none, behindCaddy]) {
        final DVIpAddress? seen = resolver.resolve(_request(
          '198.51.100.4:50000',
          <String, Object>{
            'x-forwarded-for': '203.0.113.66',
            'forwarded': 'for=203.0.113.67',
            'x-real-ip': '203.0.113.68',
            'cf-connecting-ip': '203.0.113.69',
          },
        ));
        expect(seen.toString(), '198.51.100.4');
      }
    });

    test('with no trusted proxies even a loopback peer is the client', () {
      expect(
        const DVClientAddress()
            .resolve(_request('127.0.0.1:1', <String, Object>{
              'x-forwarded-for': '203.0.113.7',
            }))
            .toString(),
        '127.0.0.1',
      );
    });

    test('no peer address is no client address, whatever the headers say', () {
      final Request request = _request(null, <String, Object>{
        'x-forwarded-for': '203.0.113.7',
        'forwarded': 'for=203.0.113.7',
        'x-real-ip': '203.0.113.7',
      });
      expect(behindCaddy.resolve(request), isNull);
      expect(const DVClientAddress().resolve(request), isNull);
    });
  });

  group('behind a trusted proxy', () {
    test('the client the proxy reports, not the proxy', () {
      expect(
        behindCaddy
            .resolve(_request('127.0.0.1:40000', <String, Object>{
              'x-forwarded-for': '203.0.113.7',
            }))
            .toString(),
        '203.0.113.7',
      );
    });

    test('an entry the client sent to the left of itself is not chosen', () {
      // The client sent X-Forwarded-For: 6.6.6.6 and the proxy appended the
      // address it actually saw.
      expect(
        behindCaddy
            .resolve(_request('127.0.0.1:40000', <String, Object>{
              'x-forwarded-for': '6.6.6.6, 203.0.113.7',
            }))
            .toString(),
        '203.0.113.7',
      );
    });

    test('a chain of trusted proxies is walked to the first untrusted hop', () {
      final DVClientAddress resolver =
          DVClientAddress.parse(const <String>['127.0.0.1', '10.0.0.0/8']);
      expect(
        resolver
            .resolve(_request('127.0.0.1:1', <String, Object>{
              'x-forwarded-for': <String>['6.6.6.6, 203.0.113.7', '10.1.2.3'],
            }))
            .toString(),
        '203.0.113.7',
        reason: 'two header lines are one list, in order',
      );
    });

    test('no header from a trusted proxy leaves the proxy as the source', () {
      expect(
        behindCaddy.resolve(_request('127.0.0.1:1')).toString(),
        '127.0.0.1',
      );
    });

    test('a garbled hop stops the walk and nothing left of it is trusted', () {
      for (final String header in <String>[
        'garbage',
        '203.0.113.7, garbage',
        '203.0.113.7,,',
        '203.0.113.7, unknown',
        '203.0.113.7 198.51.100.9',
        '999.1.1.1',
      ]) {
        expect(
          behindCaddy
              .resolve(_request('127.0.0.1:1', <String, Object>{
                'x-forwarded-for': header,
              }))
              .toString(),
          '127.0.0.1',
          reason: '"$header"',
        );
      }
    });

    test('a port on a forwarded entry is not part of the address', () {
      expect(
        behindCaddy
            .resolve(_request('127.0.0.1:1', <String, Object>{
              'x-forwarded-for': '[2001:db8::7]:4711, 203.0.113.7:5000',
            }))
            .toString(),
        '203.0.113.7',
      );
    });
  });

  group('IPv4-mapped IPv6', () {
    test('a mapped peer is trusted by the IPv4 range', () {
      expect(
        behindCaddy
            .resolve(_request('[::ffff:127.0.0.1]:40000', <String, Object>{
              'x-forwarded-for': '203.0.113.7',
            }))
            .toString(),
        '203.0.113.7',
      );
    });

    test('a mapped IPv6 range trusts the IPv4 peer', () {
      final DVClientAddress resolver =
          DVClientAddress.parse(const <String>['::ffff:10.0.0.0/104']);
      expect(
        resolver
            .resolve(_request('10.9.8.7:1', <String, Object>{
              'x-forwarded-for': '203.0.113.7',
            }))
            .toString(),
        '203.0.113.7',
      );
    });

    test('a mapped client is the same source as its IPv4 address', () {
      final DVIpAddress? mapped = behindCaddy.resolve(_request(
          '127.0.0.1:1', <String, Object>{'x-forwarded-for': '::ffff:203.0.113.7'}));
      expect(mapped, DVIpAddress.parse('203.0.113.7'));
    });
  });

  group('Forwarded', () {
    final DVClientAddress rfc7239 = DVClientAddress.parse(
      const <String>['127.0.0.1'],
      forwardedHeader: 'forwarded',
    );

    test('is read when configured, right to left', () {
      expect(
        rfc7239
            .resolve(_request('127.0.0.1:1', <String, Object>{
              'forwarded':
                  'for=6.6.6.6;proto=https, For="[2001:db8:cafe::17]:4711";by=127.0.0.1',
            }))
            .toString(),
        '2001:db8:cafe::17',
      );
    });

    test('an obfuscated or unknown node stops the walk', () {
      for (final String header in <String>[
        'for=unknown',
        'for=_hidden',
        'proto=https',
        'for="203.0.113.7',
      ]) {
        expect(
          rfc7239
              .resolve(_request('127.0.0.1:1', <String, Object>{'forwarded': header}))
              .toString(),
          '127.0.0.1',
          reason: header,
        );
      }
    });

    test('the header the application did not configure is ignored', () {
      // A proxy that writes X-Forwarded-For passes a client's Forwarded
      // through untouched -- Caddy does -- so reading both would read the
      // client's.
      expect(
        behindCaddy
            .resolve(_request('127.0.0.1:1', <String, Object>{
              'forwarded': 'for=6.6.6.6',
            }))
            .toString(),
        '127.0.0.1',
      );
      expect(
        rfc7239
            .resolve(_request('127.0.0.1:1', <String, Object>{
              'x-forwarded-for': '6.6.6.6',
            }))
            .toString(),
        '127.0.0.1',
      );
    });
  });

  group('configuration', () {
    test('refuses a range that is not one', () {
      for (final String cidr in <String>[
        '',
        'caddy',
        '10.0.0.0/33',
        '::/129',
        '10.0.0.0/',
        '/8',
        '10.0.0.0/08',
        '10.0.0.1/8',
        '10.0.0.0/8/8',
        '10.0.0.0 /8',
      ]) {
        expect(() => DVCidr.parse(cidr), throwsFormatException, reason: '"$cidr"');
      }
      expect(() => DVClientAddress.parse(const <String>['10.0.0.0/8', 'nope']),
          throwsFormatException);
      expect(() => DVClientAddress.parse(const <String>['10.0.0.0/8'],
          forwardedHeader: 'x-real-ip'), throwsFormatException);
    });

    test('a bare address is a single host', () {
      expect(DVCidr.parse('127.0.0.1').toString(), '127.0.0.1/32');
      expect(DVCidr.parse('::1').toString(), '::1/128');
      expect(DVCidr.parse('10.0.0.0/8').contains(DVIpAddress.parse('10.255.0.1')),
          isTrue);
      expect(DVCidr.parse('10.0.0.0/8').contains(DVIpAddress.parse('11.0.0.1')),
          isFalse);
      expect(DVCidr.parse('2001:db8::/32').contains(DVIpAddress.parse('2001:db8:1::1')),
          isTrue);
      expect(DVCidr.parse('0.0.0.0/0').contains(DVIpAddress.parse('::1')), isFalse,
          reason: 'an IPv4 range never contains an IPv6 address');
    });

    test('the environment adds to what the pubspec declared', () {
      final DVClientAddress resolver = DVClientAddress.fromConfiguration(
        trustedProxies: const <String>['10.0.0.0/8'],
        environment: const <String, String>{
          DVClientAddress.trustedProxiesVariable: '127.0.0.1/32, ::1/128',
        },
      );
      expect(resolver.trustedProxies.map((DVCidr c) => '$c'),
          <String>['10.0.0.0/8', '127.0.0.1/32', '::1/128']);
      expect(
        () => DVClientAddress.fromConfiguration(
          environment: const <String, String>{
            DVClientAddress.trustedProxiesVariable: '127.0.0.1/40',
          },
        ),
        throwsFormatException,
      );
    });

    test('the installed resolver answers sourceOf, and never from a header',
        () {
      addTearDown(DVClientAddress.reset);
      final Request request = _request(
          '127.0.0.1:1', <String, Object>{'x-forwarded-for': '203.0.113.7'});
      expect(DVClientAddress.sourceOf(request), '127.0.0.1');
      DVClientAddress.install(behindCaddy);
      expect(DVClientAddress.sourceOf(request), '203.0.113.7');
      expect(
        DVClientAddress.sourceOf(
            _request(null, <String, Object>{'x-forwarded-for': '203.0.113.7'})),
        DVClientAddress.unknownSource,
      );
    });

    test('a request with no peer is the one unknown source', () {
      expect(DVClientAddress.sourceOf(_request(null)),
          DVClientAddress.unknownSource);
    });

    test('a map-shaped request carries its peer under peerAddress only', () {
      expect(
        behindCaddy.resolve(<String, Object?>{
          'peerAddress': '127.0.0.1:9',
          'headers': <String, String>{'X-Forwarded-For': '203.0.113.7'},
        }).toString(),
        '203.0.113.7',
      );
      expect(
        behindCaddy.resolve(<String, Object?>{
          'headers': <String, String>{'x-forwarded-for': '203.0.113.7'},
        }),
        isNull,
      );
    });
  });
}
