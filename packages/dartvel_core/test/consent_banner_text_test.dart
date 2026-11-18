// The consent banner's words are the application's.
//
// A banner whose copy is fixed English names no company, links to no privacy
// policy and cannot say what NDPR or GDPR expect it to say, so an
// application either ships it as it is or writes its own banner -- and a
// hand-written banner is where "Reject" quietly becomes a grey link.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> consent({Object? banner}) => <String, Object?>{
      'version': '2026-11-18',
      'categories': <String, Object?>{
        'essential': <String, Object?>{'required': true},
        'analytics': <String, Object?>{'default': 'denied'},
      },
      'banner': ?banner,
    };

void main() {
  test('dartvel.analytics.consent.banner sets the words and the link', () {
    final DVConsentPolicy policy = DVConsentPolicy.fromConfig(consent(
      banner: <String, Object?>{
        'title': 'We value your privacy',
        'body': 'We use cookies to see which ads bring visitors.',
        'privacyUrl': '/privacy',
        'privacyLabel': 'Privacy policy',
        'acceptLabel': 'Accept all',
        'rejectLabel': 'Reject all',
        'settingsLabel': 'Settings',
      },
    ));
    final DVConsentBannerText text = policy.banner;
    expect(text.title, 'We value your privacy');
    expect(text.body, 'We use cookies to see which ads bring visitors.');
    expect(text.privacyUrl, '/privacy');
    expect(text.privacyLabel, 'Privacy policy');
    expect(text.acceptLabel, 'Accept all');
    expect(text.rejectLabel, 'Reject all');
    expect(text.settingsLabel, 'Settings');
  });

  test('without it the banner has plain defaults and no link', () {
    final DVConsentBannerText text =
        DVConsentPolicy.fromConfig(consent()).banner;
    expect(text.title, 'Your privacy choices');
    expect(text.body, isNull, reason: 'the banner then lists the categories');
    expect(text.privacyUrl, isNull);
    expect(text.acceptLabel, 'Accept all');
    expect(text.rejectLabel, 'Reject all');
    expect(text.settingsLabel, 'Settings');
  });

  test('a misspelt key is refused rather than ignored', () {
    expect(
        () => DVConsentPolicy.fromConfig(
            consent(banner: <String, Object?>{'tittle': 'x'})),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => '${e.message}', 'message',
            contains('accepted'))));
  });

  test('a privacy link that is not a web address or a path is refused', () {
    for (final String bad in <String>['javascript:alert(1)', 'privacy', '']) {
      expect(
          () => DVConsentPolicy.fromConfig(
              consent(banner: <String, Object?>{'privacyUrl': bad})),
          throwsArgumentError,
          reason: bad);
    }
    expect(
        DVConsentPolicy.fromConfig(consent(banner: <String, Object?>{
          'privacyUrl': 'https://example.com/privacy',
        })).banner.privacyUrl,
        'https://example.com/privacy');
  });

  test('a value that is not text is refused', () {
    expect(
        () => DVConsentPolicy.fromConfig(
            consent(banner: <String, Object?>{'title': 3})),
        throwsArgumentError);
    expect(() => DVConsentPolicy.fromConfig(consent(banner: 'hello')),
        throwsArgumentError);
  });

  test('read through dartvel.analytics like the rest of the policy', () {
    final DVAnalyticsSettings settings =
        DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': consent(banner: <String, Object?>{'title': 'Cookies'}),
    });
    expect(settings.consent.banner.title, 'Cookies');
  });
}
