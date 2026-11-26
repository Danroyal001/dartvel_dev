// Runtime off switches (`DARTVEL_OFF`): a framework feature turned off by
// setting the server's environment and restarting it, without a rebuild.
// A prod hotfix on sigmadev.digital needed a 25-minute rebuild to turn off
// one feature (the page scroll button, whose tap area covered the page).
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><meta charset="UTF-8">'
    '<title>app</title></head><body><p>hi</p></body></html>';

void main() {
  group('DVOffSwitches.parse', () {
    test('nothing set is nothing off', () {
      for (final String? raw in <String?>[null, '', '  ', ',, ,']) {
        final DVOffSwitches off = DVOffSwitches.parse(raw);
        expect(off.isEmpty, isTrue, reason: '"$raw"');
        expect(off.unknown, isEmpty);
      }
    });

    test('comma or space separated, any case, padded', () {
      final DVOffSwitches off =
          DVOffSwitches.parse(' Page-Scroll-Button,ssr-first  analytics ,cache-warm');
      expect(off.names, <String>{'page-scroll-button', 'ssr-first', 'analytics', 'cache-warm'});
      expect(off.isOff(DVOffSwitches.pageScrollButton), isTrue);
      expect(off.isOff(DVOffSwitches.ssrFirst), isTrue);
      expect(off.isOff(DVOffSwitches.analytics), isTrue);
      expect(off.isOff(DVOffSwitches.cacheWarm), isTrue);
      expect(off.unknown, isEmpty);
    });

    test('an unknown name is kept aside to be reported, never silently on', () {
      final DVOffSwitches off = DVOffSwitches.parse('page-scrol-button, analytics, module:');
      expect(off.names, <String>{'analytics'});
      expect(off.unknown, <String>['page-scrol-button', 'module:']);
      expect(off.isOff('page-scrol-button'), isFalse);
    });

    test('a module by its mount id, and analytics as the group of analytics modules', () {
      final DVOffSwitches one = DVOffSwitches.parse('module:metaPixel');
      expect(one.names, <String>{'module:metaPixel'});
      expect(one.moduleOff('metaPixel'), isTrue);
      expect(one.moduleOff('metapixel'), isTrue, reason: 'ids compare without case');
      expect(one.moduleOff('googleAnalytics', groups: const <String>['analytics']), isFalse);

      final DVOffSwitches group = DVOffSwitches.parse('analytics');
      expect(group.moduleOff('googleAnalytics', groups: const <String>['analytics']), isTrue);
      expect(group.moduleOff('woocommerce'), isFalse);
    });

    test('describes itself for the start-up log', () {
      expect(DVOffSwitches.parse('ssr-first analytics').describe(), 'analytics, ssr-first');
      expect(DVOffSwitches.none.describe(), 'none');
    });
  });

  group('the document', () {
    test('nothing off: every byte as it was, no meta tag', () {
      expect(DVOffSwitches.none.document(_shell), same(_shell));
      expect(DVOffSwitches.parse('cache-warm').document(_shell), _shell,
          reason: 'a server-only switch tells the client nothing');
    });

    test('a client switch is one meta tag in the head, read back as written', () {
      final String page = DVOffSwitches.parse('analytics page-scroll-button cache-warm').document(_shell);
      expect(
          page,
          '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>app</title>'
          '<meta name="dartvel-off" content="analytics page-scroll-button"></head>'
          '<body><p>hi</p></body></html>');
      expect(DVOffSwitches.fromPage(page).names, <String>{'analytics', 'page-scroll-button'});
      expect(DVOffSwitches.fromPage(_shell).isEmpty, isTrue);
    });

    test('a module id is escaped into the attribute and read back', () {
      final String page = DVOffSwitches.parse('module:metaPixel').document(_shell);
      expect(page, contains('<meta name="dartvel-off" content="module:metaPixel">'));
      expect(DVOffSwitches.fromPage(page).moduleOff('metaPixel'), isTrue);
    });

    test('applied twice it is applied once', () {
      final DVOffSwitches off = DVOffSwitches.parse('analytics ssr-first');
      final String once = off.document(_shell);
      expect(off.document(once), once);
    });

    test('ssr-first: the SSR-first head comes out of an SSR-first shell', () {
      final String head = dvSsrFirstHead(background: '#ffffff', darkBackground: '#000000', accent: '#b83a12');
      final String ssrFirst = _shell.replaceFirst('</head>', '$head${dvSsrFirstThemeStyle('.dvt{color:red}')}</head>');
      expect(dvIsSsrFirst(ssrFirst), isTrue);
      final String off = DVOffSwitches.parse('ssr-first').document(ssrFirst);
      expect(off, _shell);
      expect(dvIsSsrFirst(off), isFalse);
      expect(dvHasSsrFirstTheme(off), isFalse);
    });
  });

  group('DVOffSwitches.current', () {
    tearDown(() => DVOffSwitches.current = DVOffSwitches.none);

    test('can be set, for a test or a host that reads its own settings', () {
      DVOffSwitches.current = DVOffSwitches.parse('analytics');
      expect(DVOffSwitches.current.isOff(DVOffSwitches.analytics), isTrue);
    });

    test('on the server it is read from DARTVEL_OFF', () {
      DVSecrets.configure(<String, String>{dvOffVariable: 'page-scroll-button'});
      expect(DVOffSwitches.resolve().isOff(DVOffSwitches.pageScrollButton), isTrue);
    });
  });
}
