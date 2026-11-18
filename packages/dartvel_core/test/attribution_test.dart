// Where a visitor came from, kept on their device.
//
// An ad click lands on a page with utm_* and fbclid in its address. The
// first route change takes them out, and by the time the visitor fills in a
// contact form three pages later nothing on the page says which ad brought
// them. That is the silent failure here: a lead that arrives with no source
// looks exactly like one that came direct, and an ad that works reports zero
// conversions.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class MapStorage implements DVAttributionStorage {
  final Map<String, String> values = <String, String>{};

  @override
  String? read(String key) => values[key];

  @override
  void write(String key, String value) => values[key] = value;
}

void main() {
  late MapStorage storage;
  late DateTime now;

  DVAttribution device() =>
      DVAttribution(storage: storage, clock: () => now);

  setUp(() {
    storage = MapStorage();
    now = DateTime.utc(2026, 11, 18, 9);
  });

  test('an ad click is captured with every campaign parameter', () {
    final DVAttribution attribution = device();
    attribution.capture(
      Uri.parse('https://sigmadev.digital/services/web?utm_source=facebook'
          '&utm_medium=paid_social&utm_campaign=nov_launch&utm_content=video_a'
          '&utm_term=web+design&utm_id=120211&fbclid=IwAR0abc&gclid=Cj0xyz'),
      referrer: 'https://l.facebook.com/',
    );
    final DVTouch touch = attribution.lastTouch!;
    expect(touch.source, 'facebook');
    expect(touch.medium, 'paid_social');
    expect(touch.campaign, 'nov_launch');
    expect(touch.content, 'video_a');
    expect(touch.term, 'web design');
    expect(touch.id, '120211');
    expect(touch.fbclid, 'IwAR0abc');
    expect(touch.gclid, 'Cj0xyz');
    expect(touch.referrer, 'https://l.facebook.com/');
    expect(touch.landingPath, '/services/web');
    expect(touch.at, now);
    // Meta's documented _fbc format: fb.1.<creation time in ms>.<fbclid>.
    expect(touch.fbc, 'fb.1.${now.millisecondsSinceEpoch}.IwAR0abc');
  });

  test('it survives the page: a later page load reads the same touches', () {
    device().capture(
        Uri.parse('https://example.com/?utm_source=facebook&fbclid=abc'));
    now = now.add(const Duration(hours: 2));
    final DVAttribution later = device()
      ..capture(Uri.parse('https://example.com/contact'));
    expect(later.firstTouch!.source, 'facebook');
    expect(later.lastTouch!.source, 'facebook');
    expect(later.lastTouch!.fbclid, 'abc');
  });

  test('first touch is never overwritten by a later campaign', () {
    device().capture(Uri.parse('https://example.com/?utm_source=google'));
    now = now.add(const Duration(days: 3));
    final DVAttribution later = device()
      ..capture(Uri.parse('https://example.com/?utm_source=facebook'));
    expect(later.firstTouch!.source, 'google');
    expect(later.lastTouch!.source, 'facebook');
  });

  test('a direct visit does not overwrite the last campaign', () {
    device().capture(Uri.parse('https://example.com/?utm_source=facebook'));
    now = now.add(const Duration(days: 1));
    final DVAttribution later = device()
      ..capture(Uri.parse('https://example.com/pricing'));
    expect(later.lastTouch!.source, 'facebook');
    expect(later.visit, isNull,
        reason: 'a direct visit is not a new campaign to report');
  });

  test('a visit from another site is a new last touch; the own site is not',
      () {
    device().capture(Uri.parse('https://example.com/?utm_source=facebook'));
    final DVAttribution internal = device()
      ..capture(Uri.parse('https://example.com/about'),
          referrer: 'https://example.com/');
    expect(internal.lastTouch!.source, 'facebook');

    final DVAttribution external = device()
      ..capture(Uri.parse('https://example.com/blog/post'),
          referrer: 'https://www.google.com/');
    expect(external.lastTouch!.source, isNull);
    expect(external.lastTouch!.referrer, 'https://www.google.com/');
    expect(external.firstTouch!.source, 'facebook');
  });

  test('the very first visit is the first touch even when direct', () {
    final DVAttribution attribution = device()
      ..capture(Uri.parse('https://example.com/start'));
    expect(attribution.firstTouch!.landingPath, '/start');
    expect(attribution.firstTouch!.referrer, isNull);
    expect(attribution.lastTouch!.landingPath, '/start');
  });

  test('first touch lasts 90 days, then the next visit replaces it', () {
    device().capture(Uri.parse('https://example.com/?utm_source=google'));
    now = now.add(const Duration(days: 89));
    expect((device()..capture(Uri.parse('https://example.com/'))).firstTouch!
        .source, 'google');
    now = now.add(const Duration(days: 2));
    final DVAttribution expired = device()
      ..capture(Uri.parse('https://example.com/?utm_source=tiktok'));
    expect(expired.firstTouch!.source, 'tiktok');
  });

  test('only the landing is captured: a second call in a page load is not a '
      'visit', () {
    final DVAttribution attribution = device()
      ..capture(Uri.parse('https://example.com/?utm_source=facebook'));
    attribution.capture(Uri.parse('https://example.com/?utm_source=other'));
    expect(attribution.lastTouch!.source, 'facebook');
  });

  test('the tagged visit of this page load is offered for page views', () {
    final DVAttribution attribution = device()
      ..capture(Uri.parse('https://example.com/?utm_source=facebook'
          '&utm_medium=cpc&utm_campaign=launch'));
    expect(attribution.visit!.campaign, 'launch');
  });

  test('toJson is a plain map an application can send with a form', () {
    final DVAttribution attribution = device()
      ..capture(Uri.parse('https://example.com/?utm_source=facebook&fbclid=x'),
          referrer: 'https://m.facebook.com/');
    final Map<String, Object?> json = attribution.toJson();
    expect(json.keys, <String>['firstTouch', 'lastTouch']);
    final Map<String, Object?> last = json['lastTouch']! as Map<String, Object?>;
    expect(last['utm_source'], 'facebook');
    expect(last['fbclid'], 'x');
    expect(last['fbc'], startsWith('fb.1.'));
    expect(last['referrer'], 'https://m.facebook.com/');
    expect(last['landing_path'], '/');
    expect(last['at'], now.toIso8601String());
    expect(last.containsKey('utm_medium'), isFalse,
        reason: 'absent parameters are left out, not sent as null');
  });

  test('nothing captured is an empty answer, not an error', () {
    expect(device().toJson(),
        <String, Object?>{'firstTouch': null, 'lastTouch': null});
  });

  test('storage that holds garbage is treated as nothing kept', () {
    storage.values[DVAttribution.storageKey] = '{not json';
    final DVAttribution attribution = device()
      ..capture(Uri.parse('https://example.com/?utm_source=facebook'));
    expect(attribution.firstTouch!.source, 'facebook');
  });

  test('storage that throws never stops a page', () {
    final DVAttribution attribution =
        DVAttribution(storage: _ThrowingStorage(), clock: () => now)
          ..capture(Uri.parse('https://example.com/?utm_source=facebook'));
    expect(attribution.lastTouch!.source, 'facebook');
  });
}

class _ThrowingStorage implements DVAttributionStorage {
  @override
  String? read(String key) => throw StateError('blocked');

  @override
  void write(String key, String value) => throw StateError('blocked');
}
