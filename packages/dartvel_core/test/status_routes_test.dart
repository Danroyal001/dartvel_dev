// Status pages are generated per code.
//
// Error, Empty, and Loading States: "A 404 is not a blank screen; a 500 is
// not a stack trace in front of a customer, and the detail a developer needs
// goes to the log while the visitor gets a sentence." The not-found and
// offline routes were the only two; every other status a server answers with
// was a line of plain text or the host's own page.
//
// The routes live here for the same reason the two older ones do: the CLI
// declares them and writes host configuration naming them, the server
// serves them, and neither depends on dartvel_flutter, which draws them.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('the status routes', () {
    test('cover the codes a server answers a page request with', () {
      expect(dvStatusPageCodes, containsAll(<int>[403, 429, 500, 503]));
    });

    test('are each the code as its own path', () {
      for (final int code in dvStatusPageCodes) {
        expect(dvStatusPageRoute(code), '/$code');
      }
    });

    test('do not include the not-found code, which has its own page', () {
      // 404 already has DVNotFoundPage, which names the path asked for; a
      // second page for the same code would be two answers to one question.
      expect(dvStatusPageCodes, isNot(contains(404)));
    });

    test('have no route for a code nothing generates a page for', () {
      expect(dvStatusPageRoute(418), isNull);
      expect(dvStatusPageRoute(200), isNull);
    });
  });

  group('recognising one', () {
    test('a status route is an error page, so no sitemap lists it', () {
      expect(dvIsErrorPageRoute('/500'), isTrue);
      expect(dvIsErrorPageRoute('/503/'), isTrue);
      expect(dvIsErrorPageRoute('/403?from=%2Fadmin'), isTrue);
    });

    test('a page whose slug is a number under another path is not', () {
      expect(dvIsErrorPageRoute('/orders/500'), isFalse);
      expect(dvIsErrorPageRoute('/5000'), isFalse);
    });

    test('a failure is never sent back to a status page', () {
      expect(dvOfflineReturn('/500'), '/');
    });
  });
}
