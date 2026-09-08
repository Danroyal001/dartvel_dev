// A partial semantics capture must not report success.
//
// `dartvel build web` reads the semantics tree of every route in a headless
// browser and writes the crawler-visible HTML from it. Under resource pressure
// the capture can come back short -- one real build here reported "Captured 1
// of 4" and then "✅ web build successful", shipping three pages whose only
// crawler-visible content is whatever the string-literal fallback could scrape.
//
// A build that quietly ships 75% of its SEO is worse than one that fails,
// because the failure is invisible until someone checks a search result weeks
// later.
import 'package:dartvel_cli/src/build/capture_completeness.dart';
import 'package:test/test.dart';

void main() {
  test('a complete capture is silent', () {
    final DVCaptureVerdict v = dvVerifyCapture(captured: 4, expected: 4);
    expect(v.ok, isTrue);
    expect(v.message, isNull);
  });

  test('a partial capture is a failure, naming the count', () {
    final DVCaptureVerdict v = dvVerifyCapture(captured: 1, expected: 4);
    expect(v.ok, isFalse);
    expect(v.message, contains('1 of 4'));
  });

  test('the message says what it costs, not just what happened', () {
    // "Captured 1 of 4" alone reads as a progress line. What matters is that
    // three pages ship with no crawler-visible content.
    final String message = dvVerifyCapture(captured: 1, expected: 4).message!;
    expect(message, contains('3'));
    expect(message.toLowerCase(), contains('crawler'));
  });

  test('capturing nothing is a failure too, not a skip', () {
    // Zero used to be treated as "no capture step ran" and printed nothing at
    // all, which is the quietest possible way to lose every page's markup.
    final DVCaptureVerdict v = dvVerifyCapture(captured: 0, expected: 4);
    expect(v.ok, isFalse);
    expect(v.message, contains('0 of 4'));
  });

  test('no routes to capture is not a failure', () {
    // A project with no pages has nothing to prerender.
    expect(dvVerifyCapture(captured: 0, expected: 0).ok, isTrue);
  });

  test('more captured than expected is not treated as a shortfall', () {
    // Defensive: a miscount must not fail a build that captured everything.
    expect(dvVerifyCapture(captured: 5, expected: 4).ok, isTrue);
  });

  // A machine with no browser is not a machine under load.
  //
  // Both came back as "captured 0", so both failed the build -- and one of
  // them cannot be fixed by rerunning or by freeing memory, which is what the
  // message told people to do. A slim CI image, a Docker build stage and a
  // locked-down laptop have no Chrome and never will, and refusing there
  // makes `dartvel build web` a command that only runs where somebody has
  // already installed a browser.
  //
  // The capture is worth failing for when a browser ran and came back short,
  // because that is resource pressure and rerunning does fix it. It is not
  // worth failing for when there was never a browser: the build still writes
  // every page, the crawler-visible HTML is the weaker page-text form rather
  // than nothing, and the way to improve it is a command on another machine.
  group('no browser at all', () {
    test('is not a failure', () {
      final DVCaptureVerdict v =
          dvVerifyCapture(captured: 0, expected: 4, browserAvailable: false);
      expect(v.ok, isTrue);
    });

    test('still says so, because the pages are weaker for it', () {
      final DVCaptureVerdict v =
          dvVerifyCapture(captured: 0, expected: 4, browserAvailable: false);
      expect(v.message, isNotNull);
      expect(v.message, contains('prerender'));
    });

    test('does not tell anyone to free memory they have plenty of', () {
      final DVCaptureVerdict v =
          dvVerifyCapture(captured: 0, expected: 4, browserAvailable: false);
      expect(v.message, isNot(contains('resource pressure')));
      expect(v.message, isNot(contains('rerun')));
    });

    // The distinction has to be the browser, not the count. A browser that
    // launched and captured nothing is the failure this check exists for.
    test('a browser that captured nothing is still a failure', () {
      final DVCaptureVerdict v =
          dvVerifyCapture(captured: 0, expected: 4, browserAvailable: true);
      expect(v.ok, isFalse);
      expect(v.message, contains('resource pressure'));
    });

    test('a browser is assumed when nothing says otherwise', () {
      // The existing callers pass no such flag, and the safe reading of
      // silence is the strict one.
      expect(dvVerifyCapture(captured: 0, expected: 4).ok, isFalse);
    });
  });
}
