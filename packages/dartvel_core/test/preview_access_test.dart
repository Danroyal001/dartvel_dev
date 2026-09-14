// Preview Environments: who can open a preview, and that no search engine
// indexes it whatever the answer.
//
// Run against the WinterCG Request and Response the backend handlers use, so
// what is asserted is the bytes and headers a visitor actually gets.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String token = 'k3Jd9sLq0vX2mN8pR4tY6wZ1aB5cE7gH9jK2lM4nP6q';

Request get(String url, {Map<String, String> headers = const <String, String>{}}) =>
    Request(
      method: 'GET',
      url: Uri.parse(url),
      headers: Headers(headers),
      bodyStream: const Stream<List<int>>.empty(),
    );

Response page(Request request) => Response.text(
      '<!doctype html><html><head><title>Cart</title>'
      '<link rel="canonical" href="https://shop-preview-cart.preview.example.dev${request.url.path}">'
      '</head><body>cart</body></html>',
      headers: Headers(<String, String>{'content-type': 'text/html; charset=utf-8'}),
    );

Future<String> body(Response response) async =>
    response.body == null ? '' : await response.body!.text();

DVPreviewRuntime runtime(DVPreviewVisibility visibility) => DVPreviewRuntime(
      name: 'cart-c39f4dfa',
      visibility: visibility,
      linkDigest: visibility == DVPreviewVisibility.link
          ? sha256.convert(utf8.encode(token)).toString()
          : null,
      productionOrigin: 'https://shop.example.com',
    );

void main() {
  group('reading the environment', () {
    test('a process that is not a preview has no preview runtime', () {
      expect(DVPreviewRuntime.fromEnvironment(const <String, String>{}), isNull);
      expect(
        DVPreviewRuntime.fromEnvironment(
            const <String, String>{'DARTVEL_ENVIRONMENT': 'production'}),
        isNull,
      );
    });

    test('what a deployment writes is what the runtime reads', () {
      final DVPreviewIdentity id =
          DVPreviewIdentity.forBranch(app: 'shop', branch: 'feature/cart');
      final DVPreviewDeployment deployment = DVPreviewDeployment(
        identity: id,
        visibility: DVPreviewVisibility.link,
        secrets: const <String, String>{},
        linkDigest: 'abc123',
        productionOrigin: 'https://shop.example.com',
        schedules: const <String>{'nightly-report'},
      );
      final DVPreviewRuntime read =
          DVPreviewRuntime.fromEnvironment(deployment.variables)!;
      expect(read.name, id.name);
      expect(read.visibility, DVPreviewVisibility.link);
      expect(read.linkDigest, 'abc123');
      expect(read.productionOrigin, 'https://shop.example.com');
      expect(read.schedules, <String>{'nightly-report'});
    });

    test('a preview whose visibility cannot be read is refused, not opened', () {
      expect(
        () => DVPreviewRuntime.fromEnvironment(const <String, String>{
          'DARTVEL_ENVIRONMENT': 'preview',
          'DARTVEL_PREVIEW': 'cart',
          'DARTVEL_PREVIEW_VISIBILITY': 'everyone',
        }),
        throwsFormatException,
      );
      expect(
        () => DVPreviewRuntime.fromEnvironment(const <String, String>{
          'DARTVEL_ENVIRONMENT': 'preview',
          'DARTVEL_PREVIEW': 'cart',
          'DARTVEL_PREVIEW_VISIBILITY': 'link',
        }),
        throwsFormatException,
        reason: 'a link preview with no digest would admit nobody, or anybody',
      );
    });
  });

  group('never indexed', () {
    for (final DVPreviewVisibility visibility in DVPreviewVisibility.values) {
      test('${visibility.name}: every response says noindex, refusals included',
          () async {
        final DVPreviewAccess access = DVPreviewAccess(
          runtime(visibility),
          membership: (_) => DVPreviewMember.signedOut,
        );
        for (final String url in <String>[
          'https://p.example.dev/cart',
          'https://p.example.dev/robots.txt',
          'https://p.example.dev/main.dart.js',
        ]) {
          final Response response = await access.handle(get(url), page);
          expect(response.headers.get('x-robots-tag'), contains('noindex'),
              reason: '$url answered ${response.status}');
        }
      });
    }

    test('robots.txt disallows everything and needs no sign-in', () async {
      final DVPreviewAccess access = DVPreviewAccess(
        runtime(DVPreviewVisibility.members),
        membership: (_) => DVPreviewMember.signedOut,
      );
      final Response response =
          await access.handle(get('https://p.example.dev/robots.txt'), page);
      expect(response.status, 200);
      final String text = await body(response);
      expect(text, contains('User-agent: *'));
      expect(text, contains('Disallow: /'));
    });

    test('the canonical link points at production, without the link token',
        () async {
      final DVPreviewAccess access =
          DVPreviewAccess(runtime(DVPreviewVisibility.link));
      final Response response = await access.handle(
        get('https://p.example.dev/cart?x=1',
            headers: <String, String>{'cookie': 'dv_preview=$token'}),
        page,
      );
      expect(response.status, 200);
      final String html = await body(response);
      expect(html, contains('<link rel="canonical" href="https://shop.example.com/cart">'));
      expect(html, isNot(contains('preview.example.dev')));
      expect(html, isNot(contains(token)));
      expect(RegExp('rel="canonical"').allMatches(html), hasLength(1));
    });

    test('a page with no canonical gets production\'s', () async {
      final DVPreviewAccess access =
          DVPreviewAccess(runtime(DVPreviewVisibility.public));
      final Response response = await access.handle(
        get('https://p.example.dev/about'),
        (_) => Response.text('<html><head><title>x</title></head><body></body></html>',
            headers: Headers(<String, String>{'content-type': 'text/html'})),
      );
      expect(await body(response),
          contains('<link rel="canonical" href="https://shop.example.com/about"></head>'));
    });

    test('a streamed page is rewritten across chunk boundaries', () async {
      final DVPreviewAccess access =
          DVPreviewAccess(runtime(DVPreviewVisibility.public));
      final Response response = await access.handle(
        get('https://p.example.dev/cart'),
        (_) => Response(
          200,
          headers: Headers(<String, String>{'content-type': 'text/html'}),
          body: Stream<List<int>>.fromIterable(<List<int>>[
            utf8.encode('<html><head><link rel="cano'),
            utf8.encode('nical" href="https://p.example.dev/cart"></he'),
            utf8.encode('ad><body>streamed</body></html>'),
          ]),
          isStream: true,
        ),
      );
      final String html = await body(response);
      expect(html, contains('href="https://shop.example.com/cart"'));
      expect(html, contains('<body>streamed</body>'));
    });
  });

  group('members', () {
    test('without a way to ask about membership, the gate is refused', () {
      // A members preview that cannot check membership would have to either
      // admit everybody or nobody, and admitting everybody looks like working.
      expect(() => DVPreviewAccess(runtime(DVPreviewVisibility.members)),
          throwsArgumentError);
    });

    test('signed out is sent to sign in; a non-member does not get in', () async {
      DVPreviewMember who = DVPreviewMember.signedOut;
      final DVPreviewAccess access = DVPreviewAccess(
        runtime(DVPreviewVisibility.members),
        membership: (_) => who,
        signInPath: '/sign-in',
      );
      bool served = false;
      Response next(Request r) {
        served = true;
        return page(r);
      }

      final Response signedOut =
          await access.handle(get('https://p.example.dev/cart'), next);
      expect(signedOut.status, 302);
      expect(signedOut.headers.get('location'), startsWith('/sign-in'));
      expect(served, isFalse);

      final Response signIn =
          await access.handle(get('https://p.example.dev/sign-in'), next);
      expect(signIn.status, 200, reason: 'the sign-in page itself is reachable');

      served = false;
      who = DVPreviewMember.notMember;
      final Response outsider =
          await access.handle(get('https://p.example.dev/cart'), next);
      expect(outsider.status, 403);
      expect(served, isFalse);
      expect(await body(outsider), isNot(contains('cart')));

      who = DVPreviewMember.member;
      final Response member =
          await access.handle(get('https://p.example.dev/cart'), next);
      expect(member.status, 200);
    });

    test('a membership check that throws admits nobody', () async {
      final DVPreviewAccess access = DVPreviewAccess(
        runtime(DVPreviewVisibility.members),
        membership: (_) => throw StateError('org service down'),
      );
      final Response response =
          await access.handle(get('https://p.example.dev/cart'), page);
      expect(response.status, isNot(200));
    });
  });

  group('link', () {
    test('the token in the URL is exchanged for a cookie and taken out of the address',
        () async {
      final DVPreviewAccess access = DVPreviewAccess(runtime(DVPreviewVisibility.link));
      final Response response = await access.handle(
          get('https://p.example.dev/cart?dv_preview=$token&x=1'), page);
      expect(response.status, 302);
      final String location = response.headers.get('location')!;
      expect(location, isNot(contains(token)));
      expect(location, contains('/cart'));
      expect(location, contains('x=1'));
      final String cookie = response.headers.get('set-cookie')!;
      expect(cookie, contains('dv_preview=$token'));
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('Secure'));
    });

    test('no token, a wrong token, or a token for another preview is not found',
        () async {
      final DVPreviewAccess access = DVPreviewAccess(runtime(DVPreviewVisibility.link));
      bool served = false;
      Response next(Request r) {
        served = true;
        return page(r);
      }

      for (final Request request in <Request>[
        get('https://p.example.dev/cart'),
        get('https://p.example.dev/cart?dv_preview=${token.substring(1)}x'),
        get('https://p.example.dev/cart',
            headers: <String, String>{'cookie': 'dv_preview=someone-elses'}),
      ]) {
        final Response response = await access.handle(request, next);
        expect(response.status, 404, reason: '${request.url}');
      }
      expect(served, isFalse);
    });
  });

  test('public serves anyone and is still noindex', () async {
    final DVPreviewAccess access = DVPreviewAccess(runtime(DVPreviewVisibility.public));
    final Response response =
        await access.handle(get('https://p.example.dev/cart'), page);
    expect(response.status, 200);
    expect(response.headers.get('x-robots-tag'), contains('noindex'));
  });
}
