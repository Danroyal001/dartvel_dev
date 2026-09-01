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
}
