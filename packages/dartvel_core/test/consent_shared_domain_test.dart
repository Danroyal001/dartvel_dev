// One consent for every host of a site.
//
// An application served on several hosts under one registrable domain --
// `example.com`, `tools.example.com`, `<tool>.tools.example.com` -- keeps
// each host's consent in that host's own storage, which a browser never
// shares between origins. Without a shared record the visitor who accepted
// on one host is asked again on the next, and their first answer is lost
// there: nothing throws, the banner just comes back. `consent.domain` names
// the domain a cookie carries the choice across, and each case below is a way
// that silently goes wrong.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/analytics/consent_cookie.dart';
import 'package:test/test.dart';

const DVConsentCategory analytics = DVConsentCategory('analytics');
const DVConsentCategory marketing = DVConsentCategory('marketing');

DVConsentPolicy policy({String version = '2026-11-01', String? domain}) =>
    DVConsentPolicy(
      version: version,
      domain: domain,
      categories: const <DVConsentDeclaration>[
        DVConsentDeclaration(DVConsentCategory.essential, required: true),
        DVConsentDeclaration(analytics),
        DVConsentDeclaration(marketing, tracking: true),
      ],
    );

/// A browser's cookies for the site, as every host under it sees them: a
/// cookie set for `Domain=example.com` is read on each of them, one set
/// without a domain only on the host that set it.
final class FakeBrowser {
  final Map<String, ({String value, String? domain, String host, bool secure, Duration maxAge, String sameSite})> cookies =
      <String, ({String value, String? domain, String host, bool secure, Duration maxAge, String sameSite})>{};

  FakeJar on(String host, {bool secure = true}) => FakeJar(this, host, secure);
}

final class FakeJar implements DVConsentCookieJar {
  FakeJar(this.browser, this.host, this.secure);

  final FakeBrowser browser;
  @override
  final String host;
  @override
  final bool secure;

  @override
  String? read(String name) {
    final c = browser.cookies[name];
    if (c == null) return null;
    final bool visible = c.domain == null
        ? c.host == host
        : host == c.domain || host.endsWith('.${c.domain}');
    return visible ? c.value : null;
  }

  @override
  void write(String name, String value,
      {String? domain, required bool secure, required Duration maxAge, required String sameSite}) {
    browser.cookies[name] = (value: value, domain: domain, host: host, secure: secure, maxAge: maxAge, sameSite: sameSite);
  }
}

Future<DVConsent> open(DVConsentPolicy policy, DVConsentCookieJar? jar,
    {DVDatabaseAdapter? database, DateTime Function()? clock}) async {
  final DVConsent consent = DVConsent(
    policy: policy,
    database: database ?? MemoryDVDatabaseAdapter(),
    installId: 'install-${jar?.host}',
    clock: clock,
    sharedCookie: jar,
    onDiagnostic: (String code, String message) {},
  );
  await consent.ensureSchema();
  await consent.load();
  return consent;
}

void main() {
  group('consent.domain in pubspec.yaml', () {
    Map<String, Object?> config(Object? domain) => <String, Object?>{
          'version': '1',
          'domain': domain,
          'categories': <String, Object?>{'analytics': null},
        };

    test('is read, lower-cased, without a leading dot', () {
      expect(DVConsentPolicy.fromConfig(config('.Example.com')).domain, 'example.com');
      expect(DVConsentPolicy.fromConfig(config('tools.example.com')).domain, 'tools.example.com');
    });

    test('is optional: without it consent stays with each host', () {
      final Map<String, Object?> without = config(null)..remove('domain');
      expect(DVConsentPolicy.fromConfig(without).domain, isNull);
    });

    test('a public suffix is refused: a browser drops the cookie and nobody is told', () {
      for (final String suffix in <String>['com', 'co.uk', 'github.io']) {
        expect(() => DVConsentPolicy.fromConfig(config(suffix)), throwsArgumentError, reason: suffix);
      }
    });

    test('an address or a name that is not a domain is refused', () {
      for (final String bad in <String>['localhost', '127.0.0.1', 'not a host', '']) {
        expect(() => DVConsentPolicy.fromConfig(config(bad)), throwsArgumentError, reason: bad);
      }
    });
  });

  group('a choice made on one host', () {
    late FakeBrowser browser;
    setUp(() => browser = FakeBrowser());

    test('is answered on every other host under the domain: no banner there', () async {
      final DVConsent first = await open(policy(domain: 'example.com'), browser.on('word-counter.tools.example.com'));
      expect(first.needsPrompt, isTrue);
      expect(await first.record(<DVConsentCategory, bool>{analytics: true, marketing: true}, prompt: DVConsentPrompt.banner), isTrue);

      for (final String host in <String>['example.com', 'qr-code.tools.example.com', 'tools.example.com']) {
        final DVConsent other = await open(policy(domain: 'example.com'), browser.on(host));
        expect(other.needsPrompt, isFalse, reason: host);
        expect(other.isGranted(analytics), isTrue, reason: host);
        expect(other.isGranted(marketing), isTrue, reason: host);
      }
    });

    test('is kept as this host\'s own record too, so the evidence is where the data is', () async {
      final DVConsent first = await open(policy(domain: 'example.com'), browser.on('a.example.com'));
      await first.record(<DVConsentCategory, bool>{analytics: true, marketing: false}, prompt: DVConsentPrompt.banner);
      final DVConsent other = await open(policy(domain: 'example.com'), browser.on('b.example.com'));
      final List<DVConsentRecord> records = await other.records();
      expect(records, hasLength(1));
      expect(records.single.answers, <String, bool>{'analytics': true, 'marketing': false});
      expect(records.single.prompt, DVConsentPrompt.banner);
      expect(records.single.policyVersion, '2026-11-01');
    });

    test('a rejection carries too: nobody is asked twice after saying no', () async {
      final DVConsent first = await open(policy(domain: 'example.com'), browser.on('a.example.com'));
      await first.record(<DVConsentCategory, bool>{analytics: false, marketing: false}, prompt: DVConsentPrompt.banner);
      final DVConsent other = await open(policy(domain: 'example.com'), browser.on('b.example.com'));
      expect(other.needsPrompt, isFalse);
      expect(other.isGranted(analytics), isFalse);
    });

    test('the cookie is for the domain, Secure, SameSite=Lax, for a year', () async {
      final DVConsent first = await open(policy(domain: 'example.com'), browser.on('a.tools.example.com'));
      await first.record(<DVConsentCategory, bool>{analytics: true}, prompt: DVConsentPrompt.banner);
      final c = browser.cookies[DVConsentCookie.name]!;
      expect(c.domain, 'example.com');
      expect(c.secure, isTrue);
      expect(c.sameSite, 'Lax');
      expect(c.maxAge, const Duration(days: 365));
      // A cookie value is a token: no spaces, commas, semicolons or quotes.
      expect(c.value, matches(RegExp(r'^[A-Za-z0-9._-]+$')));
    });

    test('over plain http (a local run) the cookie is not marked Secure, or the browser drops it', () async {
      final DVConsent first = await open(policy(domain: 'example.com'), browser.on('a.example.com', secure: false));
      await first.record(<DVConsentCategory, bool>{analytics: true}, prompt: DVConsentPrompt.banner);
      expect(browser.cookies[DVConsentCookie.name]!.secure, isFalse);
    });

    test('a host outside the domain keeps its choice to itself', () async {
      final DVConsent first = await open(policy(domain: 'example.com'), browser.on('localhost'));
      await first.record(<DVConsentCategory, bool>{analytics: true}, prompt: DVConsentPrompt.banner);
      expect(browser.cookies[DVConsentCookie.name]?.domain, isNull);
      final DVConsent other = await open(policy(domain: 'example.com'), browser.on('a.example.com'));
      expect(other.needsPrompt, isTrue);
    });

    test('without consent.domain nothing is shared, exactly as before', () async {
      final DVConsent first = await open(policy(), browser.on('a.example.com'));
      await first.record(<DVConsentCategory, bool>{analytics: true}, prompt: DVConsentPrompt.banner);
      expect(browser.cookies, isEmpty);
    });
  });

  group('what the shared cookie is trusted with', () {
    late FakeBrowser browser;
    setUp(() => browser = FakeBrowser());

    test('a choice under another version of the categories is not consent to this one', () async {
      final DVConsent old = await open(policy(version: 'v1', domain: 'example.com'), browser.on('a.example.com'));
      await old.record(<DVConsentCategory, bool>{analytics: true, marketing: true}, prompt: DVConsentPrompt.banner);
      final DVConsent other = await open(policy(version: 'v2', domain: 'example.com'), browser.on('b.example.com'));
      expect(other.needsPrompt, isTrue);
      expect(other.isGranted(marketing), isFalse);
    });

    test('an unreadable cookie is no answer, and nothing throws', () async {
      for (final String garbage in <String>['', 'x', 'v1.%%%', 'v1.${base64Url.encode(utf8.encode('[1,2]'))}', 'v9.e30']) {
        browser.cookies[DVConsentCookie.name] =
            (value: garbage, domain: 'example.com', host: 'a.example.com', secure: true, maxAge: Duration.zero, sameSite: 'Lax');
        final DVConsent consent = await open(policy(domain: 'example.com'), browser.on('b.example.com'));
        expect(consent.needsPrompt, isTrue, reason: garbage);
      }
    });

    test('a category the policy does not declare is ignored, and a required one stays granted', () async {
      final String forged = DVConsentCookie.encode(
          version: '2026-11-01', answers: <String, bool>{'analytics': true, 'surveillance': true, 'essential': false}, recordedAt: DateTime.utc(2026, 11, 20), prompt: DVConsentPrompt.banner);
      browser.cookies[DVConsentCookie.name] = (value: forged, domain: 'example.com', host: 'a.example.com', secure: true, maxAge: Duration.zero, sameSite: 'Lax');
      final DVConsent consent = await open(policy(domain: 'example.com'), browser.on('b.example.com'));
      expect(consent.isGranted(analytics), isTrue);
      expect(consent.isGranted(DVConsentCategory.essential), isTrue);
      expect((await consent.records()).single.answers.keys, isNot(contains('surveillance')));
    });
  });

  group('hosts that answered before the cookie existed', () {
    test('an earlier answer is shared on the next visit, so the other hosts stop asking', () async {
      final FakeBrowser browser = FakeBrowser();
      final DVDatabaseAdapter database = MemoryDVDatabaseAdapter();
      // Answered under a build without consent.domain: no cookie.
      final DVConsent before = await open(policy(), browser.on('example.com'), database: database);
      await before.record(<DVConsentCategory, bool>{analytics: true, marketing: true}, prompt: DVConsentPrompt.banner);
      expect(browser.cookies, isEmpty);
      // The next build names the domain; the same host's stored answer is shared on load.
      await open(policy(domain: 'example.com'), browser.on('example.com'), database: database);
      final DVConsent tool = await open(policy(domain: 'example.com'), browser.on('qr.tools.example.com'));
      expect(tool.needsPrompt, isFalse);
      expect(tool.isGranted(marketing), isTrue);
    });

    test('the newer choice wins: a withdrawal on one host reaches a host that had granted', () async {
      final FakeBrowser browser = FakeBrowser();
      DateTime now = DateTime.utc(2026, 11, 20, 9);
      final DVDatabaseAdapter toolDb = MemoryDVDatabaseAdapter();
      final DVConsent tool = await open(policy(domain: 'example.com'), browser.on('a.example.com'), database: toolDb, clock: () => now);
      await tool.record(<DVConsentCategory, bool>{analytics: true, marketing: true}, prompt: DVConsentPrompt.banner);
      now = now.add(const Duration(hours: 1));
      final DVConsent apex = await open(policy(domain: 'example.com'), browser.on('example.com'), clock: () => now);
      await apex.record(<DVConsentCategory, bool>{marketing: false}, prompt: DVConsentPrompt.settingsScreen);
      now = now.add(const Duration(hours: 1));
      final DVConsent again = await open(policy(domain: 'example.com'), browser.on('a.example.com'), database: toolDb, clock: () => now);
      expect(again.isGranted(marketing), isFalse);
      expect(again.isGranted(analytics), isTrue);
    });

    test('an older cookie does not overwrite a newer answer on this host; this host shares its own', () async {
      final FakeBrowser browser = FakeBrowser();
      final String stale = DVConsentCookie.encode(
          version: '2026-11-01', answers: <String, bool>{'analytics': true, 'marketing': true}, recordedAt: DateTime.utc(2026, 1, 1), prompt: DVConsentPrompt.banner);
      final DVDatabaseAdapter database = MemoryDVDatabaseAdapter();
      final DVConsent here = await open(policy(), browser.on('a.example.com'), database: database, clock: () => DateTime.utc(2026, 11, 20));
      await here.record(<DVConsentCategory, bool>{analytics: false, marketing: false}, prompt: DVConsentPrompt.banner);
      browser.cookies[DVConsentCookie.name] = (value: stale, domain: 'example.com', host: 'b.example.com', secure: true, maxAge: Duration.zero, sameSite: 'Lax');
      final DVConsent reopened = await open(policy(domain: 'example.com'), browser.on('a.example.com'), database: database, clock: () => DateTime.utc(2026, 11, 21));
      expect(reopened.isGranted(marketing), isFalse);
      final DVConsentSharedChoice shared = DVConsentCookie.decode(browser.cookies[DVConsentCookie.name]!.value)!;
      expect(shared.answers['marketing'], isFalse);
    });
  });
}
