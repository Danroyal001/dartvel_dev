// A page declares middleware too, and nothing has ever asked what a page can
// actually run.
//
// NEW_SPEC.md gives the page form as the first example under Middleware:
//
//     @DVUseMiddleware([DVMiddlewares.auth, ...])
//     @DVPage()
//     Widget _checkoutPage(BuildContext context) => Checkout.Page();
//
// The nineteen keys were classified once, for the backend chain, against a
// shelf Request. Nine of those run inside an HTTP server and a page has no
// server: there is no Content-Length to check before reading a body, no
// response whose headers a page could set, and no second caller to rate
// limit -- the caller is the application itself. Reusing the backend sets
// for a page would accept every one of them and run none, which is the
// failure the backend sets were written to end, moved one scope sideways.
//
// So the page scope gets its own answer for every key, and this holds the
// two facts that make the answer worth anything: every key has one, and a
// key the page cannot run says where it belongs instead.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// The keys `DVMiddlewares` declares, read out of the annotation.
///
/// Listed there and nowhere else on purpose. A copy written next to the
/// check would agree with itself and prove nothing.
Set<String> _declared() {
  final File source = File('lib/src/annotations/annotations.dart');
  expect(source.existsSync(), isTrue,
      reason: 'annotations.dart is not where this test expects it');
  final String text = source.readAsStringSync();
  final int at = text.indexOf('class DVMiddlewares {');
  expect(at, greaterThan(-1));
  final String body = text.substring(at, text.indexOf('\n}', at));
  return RegExp(r"DVMiddlewareKey\('([A-Za-z_][A-Za-z0-9_]*)'\)")
      .allMatches(body)
      .map((RegExpMatch m) => m.group(1)!)
      .toSet();
}

void main() {
  group('what a page route can run', () {
    test('auth is one, because a page can be refused before it activates', () {
      expect(dvPageMiddlewareRefusal('auth'), isNull);
    });

    test('maintenance is one, for the same reason', () {
      expect(dvPageMiddlewareRefusal('maintenance'), isNull);
    });

    test('a body limit is not, and the refusal says where limits live', () {
      // The interesting half. A page declaring bodyLimit is a developer who
      // believes something is being capped; nothing is, and nothing can be,
      // because the page never reads a request body. Accepting the key
      // quietly is the exact bug the backend sets closed.
      final String? reason = dvPageMiddlewareRefusal('bodyLimit');

      expect(reason, isNotNull);
      expect(reason, contains('@DVBackendFunction'));
    });

    test('policy is not, and points at the argument that carries a name', () {
      // Same shape as the backend refusal for the same key: nothing in
      // @DVUseMiddleware says which policy, and @DVPage(policy: ...) does.
      final String? reason = dvPageMiddlewareRefusal('policy');

      expect(reason, isNotNull);
      expect(reason, contains('@DVPage(policy:'));
    });

    test('every key the annotation declares gets a real answer', () {
      // The drift guard. A key added to DVMiddlewares and to no page set
      // would fall through to a generic refusal that names no alternative,
      // which reads to whoever hits it as Dartvel not knowing its own key.
      for (final String key in _declared()) {
        final String? reason = dvPageMiddlewareRefusal(key);
        if (dvPageMiddlewareKeysBuilt.contains(key)) {
          expect(reason, isNull, reason: '$key is built for pages');
          continue;
        }
        expect(
          reason,
          isNotNull,
          reason: '$key has no page-scope answer at all',
        );
        expect(
          dvPageMiddlewareKeysUnavailableReason.containsKey(key),
          isTrue,
          reason: '$key falls through to the generic refusal, which names '
              'nothing a developer can do next',
        );
      }
    });

    test('a name nobody declared is refused rather than run', () {
      expect(dvPageMiddlewareRefusal('notARealMiddleware'), isNotNull);
    });

    test('no page set claims a key the annotation does not declare', () {
      final Set<String> all = <String>{
        ...dvPageMiddlewareKeysBuilt,
        ...dvPageMiddlewareKeysUnavailableReason.keys,
      };
      expect(all.difference(_declared()), isEmpty);
    });

    test('and no key is both built and refused', () {
      expect(
        dvPageMiddlewareKeysBuilt
            .intersection(dvPageMiddlewareKeysUnavailableReason.keys.toSet()),
        isEmpty,
        reason: 'a key in both sets is run or refused depending on which the '
            'generator reads first',
      );
    });
  });
}
