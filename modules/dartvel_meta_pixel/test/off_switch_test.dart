// DARTVEL_OFF=analytics (or module:<id>): the pixel switched off at runtime.
// The client loads no Meta script and the server forwards nothing to the
// Conversions API, whatever the mount or the environment configures.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_meta_pixel/dartvel_meta_pixel.dart';
import 'package:dartvel_meta_pixel/src/browser.dart';
import 'package:dartvel_meta_pixel/src/runtime.dart';
import 'package:test/test.dart';

class _Browser implements MetaPixelBrowser {
  final List<String> log = <String>[];
  @override
  bool get available => true;
  @override
  String? pageUrl = 'https://example.com/';
  @override
  String? userAgent = 'Test';
  @override
  void load(String pixelId, {required String scriptUrl}) => log.add('load $pixelId');
  @override
  void track(String name, Map<String, Object?> data, {required String eventId, required bool custom}) => log.add('track $name');
  @override
  void consent({required bool granted}) => log.add('consent');
  @override
  String? cookie(String name) => null;
  @override
  void setCookie(String name, String value, {required Duration maxAge}) {}
  @override
  String? queryParameter(String name) => null;
}

DVModule _mount(String id) => DVModule(id: id, mountPath: '/', config: const <String, Object?>{
      'config': <String, Object?>{'pixelId': '1234567890'},
    });

void main() {
  late _Browser browser;
  late List<Map<String, Object?>> relayed;
  late MetaPixelRuntime saved;

  setUp(() {
    saved = MetaPixelRuntime.instance;
    browser = _Browser();
    relayed = <Map<String, Object?>>[];
  });
  tearDown(() {
    MetaPixelRuntime.instance = saved;
    DVOffSwitches.current = DVOffSwitches.none;
  });

  MetaPixelRuntime runtime(DVModuleEnvironment environment) => MetaPixelRuntime.instance = MetaPixelRuntime(
        browser: browser,
        environment: environment,
        consentGranted: (_) => true,
        relay: (Map<String, Object?> event) async => relayed.add(event),
        serverPixelId: () async => '1234567890',
      );

  for (final String off in <String>['analytics', 'module:metaPixel']) {
    test('$off: a browser loads nothing and sends nothing', () async {
      DVOffSwitches.current = DVOffSwitches.parse(off);
      final MetaPixelRuntime pixel = runtime(DVModuleEnvironment.web);
      startMetaPixel(_mount('metaPixel'));
      expect(const MetaPixel().isConfigured, isFalse);
      await const MetaPixel().lead(contentName: 'Callback');
      await const MetaPixel().pageView();
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
      // Set up in code afterwards: still off.
      pixel.config = const MetaPixelConfig(pixelId: '1234567890');
      await const MetaPixel().lead(contentName: 'Callback');
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
    });

    test('$off: the server forwards nothing and names no pixel', () async {
      DVOffSwitches.current = DVOffSwitches.parse(off);
      final MetaPixelRuntime pixel = runtime(DVModuleEnvironment.backend);
      startMetaPixel(_mount('metaPixel'));
      expect(pixel.settings(), <String, Object?>{'pixelId': null});
      final Map<String, Object?> answer = await pixel.collect(<String, Object?>{'name': 'Lead', 'url': 'https://example.com/'});
      expect(answer['sent'], isFalse);
      expect(answer['reason'], 'the pixel is switched off');
    });
  }

  test('another module switched off leaves the pixel on', () async {
    DVOffSwitches.current = DVOffSwitches.parse('module:googleAnalytics');
    runtime(DVModuleEnvironment.web);
    startMetaPixel(_mount('metaPixel'));
    expect(const MetaPixel().isConfigured, isTrue);
  });
}
