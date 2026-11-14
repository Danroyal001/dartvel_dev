// The page shell says which page is on screen, once per page, and whatever
// measures page views listens. Nothing in an application is asked to call it.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  setUp(DVPageViews.resetForTesting);

  test('a listener hears each page shown', () {
    final List<String> seen = <String>[];
    DVPageViews.addListener((DVPageView view) => seen.add('${view.location}'));
    DVPageViews.report(Uri.parse('https://example.com/'));
    DVPageViews.report(Uri.parse('https://example.com/pricing?plan=pro'));
    expect(seen, <String>[
      'https://example.com/',
      'https://example.com/pricing?plan=pro',
    ]);
  });

  test('the same page reported twice running is one view', () {
    // A page shell rebuilds, and its router tells it the address again.
    final List<DVPageView> seen = <DVPageView>[];
    DVPageViews.addListener(seen.add);
    DVPageViews.report(Uri.parse('https://example.com/a'));
    DVPageViews.report(Uri.parse('https://example.com/a'));
    expect(seen, hasLength(1));
  });

  test('a fragment is the same page', () {
    final List<DVPageView> seen = <DVPageView>[];
    DVPageViews.addListener(seen.add);
    DVPageViews.report(Uri.parse('https://example.com/docs'));
    DVPageViews.report(Uri.parse('https://example.com/docs#install'));
    expect(seen, hasLength(1));
  });

  test('coming back to a page is a view of it', () {
    final List<DVPageView> seen = <DVPageView>[];
    DVPageViews.addListener(seen.add);
    DVPageViews.report(Uri.parse('https://example.com/a'));
    DVPageViews.report(Uri.parse('https://example.com/b'));
    DVPageViews.report(Uri.parse('https://example.com/a'));
    expect(seen, hasLength(3));
  });

  test('a listener added later is told the page already on screen', () {
    // A module that waits for consent starts listening after the first page
    // was shown, and that page is the one most visits consist of.
    DVPageViews.report(Uri.parse('https://example.com/landing'), title: 'Hi');
    final List<DVPageView> seen = <DVPageView>[];
    DVPageViews.addListener(seen.add);
    expect(seen.single.location.path, '/landing');
    expect(seen.single.title, 'Hi');
  });

  test('a listener that throws does not stop the others', () {
    final List<DVPageView> seen = <DVPageView>[];
    DVPageViews.addListener((DVPageView _) => throw StateError('broken'));
    DVPageViews.addListener(seen.add);
    DVPageViews.report(Uri.parse('https://example.com/a'));
    expect(seen, hasLength(1));
  });

  test('a removed listener hears nothing more', () {
    final List<DVPageView> seen = <DVPageView>[];
    DVPageViews.addListener(seen.add);
    DVPageViews.removeListener(seen.add);
    DVPageViews.report(Uri.parse('https://example.com/a'));
    expect(seen, isEmpty);
  });
}
