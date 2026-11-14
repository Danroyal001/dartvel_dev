// The registrable domain of a host, by the Public Suffix List.
//
// A session that spans an application's hosts is a cookie with a Domain
// attribute, and the domain it names decides who else receives it. "The last
// two labels" names co.uk for shop.co.uk -- a cookie for every company in the
// United Kingdom, which a browser refuses, so sign-in answers 200 and nobody
// is signed in -- and github.io for alice.github.io, which would hand Alice's
// session to every other GitHub Pages site if a browser accepted it. Both
// sections of the list count, the ICANN one and the private one, because
// browsers apply both.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('the registrable domain', () {
    test('of an ordinary name is its last two labels', () {
      expect(dvRegistrableDomain('example.com'), 'example.com');
      expect(dvRegistrableDomain('app.example.com'), 'example.com');
      expect(dvRegistrableDomain('x.tools.sigmadev.digital'), 'sigmadev.digital');
    });

    test('below a multi-label public suffix keeps three labels', () {
      expect(dvRegistrableDomain('shop.co.uk'), 'shop.co.uk');
      expect(dvRegistrableDomain('a.b.shop.co.uk'), 'shop.co.uk');
      expect(dvRegistrableDomain('shop.example.com.au'), 'example.com.au');
      expect(dvRegistrableDomain('www.example.com.ng'), 'example.com.ng');
    });

    test('counts the private section, as browsers do', () {
      expect(dvRegistrableDomain('alice.github.io'), 'alice.github.io');
      expect(dvRegistrableDomain('www.alice.github.io'), 'alice.github.io');
      expect(dvRegistrableDomain('my-app.vercel.app'), 'my-app.vercel.app');
    });

    test('of a public suffix itself is none', () {
      for (final String suffix in <String>[
        'com',
        'co.uk',
        'com.au',
        'github.io',
        'vercel.app',
      ]) {
        expect(dvRegistrableDomain(suffix), isNull, reason: suffix);
        expect(dvIsPublicSuffix(suffix), isTrue, reason: suffix);
      }
      expect(dvIsPublicSuffix('example.com'), isFalse);
      expect(dvIsPublicSuffix('alice.github.io'), isFalse);
    });

    test('follows wildcard and exception rules', () {
      // *.ck and !www.ck: every name under ck is a suffix but www.ck.
      expect(dvIsPublicSuffix('anything.ck'), isTrue);
      expect(dvRegistrableDomain('shop.anything.ck'), 'shop.anything.ck');
      expect(dvRegistrableDomain('www.ck'), 'www.ck');
      expect(dvRegistrableDomain('a.www.ck'), 'www.ck');
    });

    test('treats an unlisted top-level label as a suffix of one label', () {
      // The default rule "*": .test is reserved and in no list.
      expect(dvRegistrableDomain('app.example.test'), 'example.test');
      expect(dvIsPublicSuffix('test'), isTrue);
    });

    test('reads internationalised suffixes in their punycode form', () {
      // 公司.cn is a public suffix; hosts arrive as punycode.
      expect(dvIsPublicSuffix('xn--55qx5d.cn'), isTrue);
      expect(dvRegistrableDomain('shop.xn--55qx5d.cn'), 'shop.xn--55qx5d.cn');
    });

    test('normalises case, a trailing dot and a port', () {
      expect(dvRegistrableDomain('APP.Example.COM.'), 'example.com');
      expect(dvRegistrableDomain('app.example.com:8443'), 'example.com');
    });

    test('of an address, localhost or nonsense is none', () {
      for (final String host in <String>[
        '127.0.0.1',
        '[::1]',
        '::1',
        'localhost',
        '',
        '.',
        'bad..example.com',
      ]) {
        expect(dvRegistrableDomain(host), isNull, reason: host);
      }
    });
  });
}
