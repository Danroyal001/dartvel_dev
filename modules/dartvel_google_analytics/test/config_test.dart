// The settings, read from the mount.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_google_analytics/dartvel_google_analytics.dart';
import 'package:dartvel_google_analytics/src/browser.dart';
import 'package:test/test.dart';

void main() {
  setUp(DVSecrets.reset);
  tearDown(DVSecrets.reset);

  test('the mount\'s settings are read', () {
    final GoogleAnalyticsConfig config =
        GoogleAnalyticsConfig.fromModuleConfig(<String, Object?>{
      'measurementId': 'G-ABC123XYZ9',
      'consent': 'analytics',
      'pageViews': 'automatic',
      'collectInEu': true,
      'origin': 'https://example.com',
    });
    expect(config.isConfigured, isTrue);
    expect(config.consentCategory, 'analytics');
    expect(config.pageViews, GoogleAnalyticsPageViews.automatic);
    expect(config.collectInEu, isTrue);
    expect(config.origin, 'https://example.com');
  });

  test('with nothing set the defaults apply and it is not configured', () {
    const GoogleAnalyticsConfig config = GoogleAnalyticsConfig();
    expect(config.isConfigured, isFalse);
    expect(config.consentCategory, 'product');
    expect(config.pageViews, GoogleAnalyticsPageViews.manual);
    expect(config.excludes('/__studio'), isTrue);
  });

  test('the server reads the measurement id from its environment', () {
    DVSecrets.configure(<String, String>{'GA4_MEASUREMENT_ID': 'G-SERVER1234'});
    expect(const GoogleAnalyticsConfig().resolvedMeasurementId, 'G-SERVER1234');
  });

  test('something that is not a measurement id is not configured', () {
    expect(const GoogleAnalyticsConfig(measurementId: 'UA-1234-5').isConfigured,
        isFalse);
    expect(const GoogleAnalyticsConfig(measurementId: '1234567890').isConfigured,
        isFalse);
  });

  test('the API secret in the mount is refused by name: it would be '
      'compiled into the client', () {
    expect(
      () => GoogleAnalyticsConfig.fromModuleConfig(
          <String, Object?>{'measurementId': 'G-ABC123XYZ9', 'apiSecret': 'x'}),
      throwsA(isA<ArgumentError>().having((ArgumentError e) => '${e.message}',
          'message', contains('GA4_API_SECRET'))),
    );
  });

  test('a setting or a page view mode it does not know is refused', () {
    expect(
      () => GoogleAnalyticsConfig.fromModuleConfig(
          <String, Object?>{'measurementID': 'G-ABC123XYZ9'}),
      throwsArgumentError,
    );
    expect(
      () => GoogleAnalyticsConfig.fromModuleConfig(
          <String, Object?>{'pageViews': 'sometimes'}),
      throwsArgumentError,
    );
  });

  test('the client id is the last two numbers of the _ga cookie', () {
    expect(dvGoogleAnalyticsClientIdFromCookie('GA1.1.123456789.1700000000'),
        '123456789.1700000000');
    expect(dvGoogleAnalyticsClientIdFromCookie('GA1.2.44.55'), '44.55');
    // Not that shape: sent whole, which Google also accepts.
    expect(dvGoogleAnalyticsClientIdFromCookie('opaque'), 'opaque');
    expect(dvGoogleAnalyticsClientIdFromCookie(null), isNull);
    expect(dvGoogleAnalyticsClientIdFromCookie(' '), isNull);
  });
}
