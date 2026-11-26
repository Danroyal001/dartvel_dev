// DARTVEL_OFF=analytics (or module:<id>): Google Analytics switched off at
// runtime. The client loads no Google tag and the server forwards nothing to
// the Measurement Protocol, whatever the mount or the environment configures.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_google_analytics/dartvel_google_analytics.dart';
import 'package:dartvel_google_analytics/src/browser.dart';
import 'package:dartvel_google_analytics/src/runtime.dart';
import 'package:test/test.dart';

class _Browser implements GoogleAnalyticsBrowser {
  final List<String> log = <String>[];
  @override
  bool get available => true;
  @override
  String? clientId = '123456789.1700000000';
  @override
  String? sessionId = '1700000123';
  @override
  String? pageUrl = 'https://example.com/';
  @override
  String? pageTitle = 'Home';
  @override
  void load(String measurementId, {required String scriptUrl, required bool sendPageView}) => log.add('load $measurementId');
  @override
  void event(String name, Map<String, Object?> params) => log.add('event $name');
  @override
  void consentDefaults() => log.add('consent defaults');
  @override
  void consent({required bool granted}) => log.add('consent');
}

DVModule _mount(String id) => DVModule(id: id, mountPath: '/', config: const <String, Object?>{
      'config': <String, Object?>{'measurementId': 'G-ABC1234567'},
    });

void main() {
  late _Browser browser;
  late List<Map<String, Object?>> relayed;
  late GoogleAnalyticsRuntime saved;

  setUp(() {
    saved = GoogleAnalyticsRuntime.instance;
    browser = _Browser();
    relayed = <Map<String, Object?>>[];
  });
  tearDown(() {
    GoogleAnalyticsRuntime.instance = saved;
    DVOffSwitches.current = DVOffSwitches.none;
  });

  GoogleAnalyticsRuntime runtime(DVModuleEnvironment environment) => GoogleAnalyticsRuntime.instance = GoogleAnalyticsRuntime(
        browser: browser,
        environment: environment,
        consentGranted: (_) => true,
        consentRequired: () => false,
        relay: (Map<String, Object?> event) async => relayed.add(event),
      );

  for (final String off in <String>['analytics', 'module:googleAnalytics']) {
    test('$off: a browser loads nothing and sends nothing', () async {
      DVOffSwitches.current = DVOffSwitches.parse(off);
      final GoogleAnalyticsRuntime analytics = runtime(DVModuleEnvironment.web);
      startGoogleAnalytics(_mount('googleAnalytics'));
      expect(const GoogleAnalytics().isConfigured, isFalse);
      await const GoogleAnalytics().generateLead();
      await const GoogleAnalytics().pageView();
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
      analytics.config = const GoogleAnalyticsConfig(measurementId: 'G-ABC1234567');
      await const GoogleAnalytics().generateLead();
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
    });

    test('$off: the server forwards nothing', () async {
      DVOffSwitches.current = DVOffSwitches.parse(off);
      final GoogleAnalyticsRuntime analytics = runtime(DVModuleEnvironment.backend);
      startGoogleAnalytics(_mount('googleAnalytics'));
      final Map<String, Object?> answer = await analytics.collect(<String, Object?>{'name': 'generate_lead', 'clientId': '1.2'});
      expect(answer['sent'], isFalse);
      expect(answer['reason'], 'Google Analytics is switched off');
    });
  }

  test('another module switched off leaves it on', () async {
    DVOffSwitches.current = DVOffSwitches.parse('module:metaPixel');
    runtime(DVModuleEnvironment.web);
    startGoogleAnalytics(_mount('googleAnalytics'));
    expect(const GoogleAnalytics().isConfigured, isTrue);
  });
}
