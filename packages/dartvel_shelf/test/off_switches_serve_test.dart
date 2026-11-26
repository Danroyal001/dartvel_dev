// DARTVEL_OFF on the web-server: what a switch changes in the documents it
// serves, through the one render path (handleSsrFallback), with no rebuild.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:test/test.dart';

const String _plainShell = '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>App</title></head>'
    '<body><script src="flutter_bootstrap.js" async></script></body></html>';

String _ssrFirstShell() => _plainShell.replaceFirst(
    '</head>',
    '${dvSsrFirstHead(background: '#ffffff', darkBackground: '#000000', accent: '#b83a12')}'
        '${dvSsrFirstThemeStyle('.dvt h1{font-size:2rem}')}</head>');

Directory _site(String shell) {
  final Directory root = Directory.systemTemp.createTempSync('dv-off-switches-');
  File('${root.path}/index.html').writeAsStringSync(shell);
  File('${root.path}/dartvel_routes.json').writeAsStringSync(jsonEncode(<String, Object?>{
    'routes': <String, Object?>{
      '/': <String, Object?>{'title': 'Home', 'text': <String>['Welcome', 'Read on']},
      '/pricing': <String, Object?>{'title': 'Pricing', 'text': <String>['Plans']},
      '/private': <String, Object?>{'guarded': true},
    },
  }));
  return root;
}

Request _get(String path) => Request(
      method: 'GET',
      url: Uri.parse('http://localhost$path'),
      headers: Headers(const <String, String>{}),
      bodyStream: const Stream<List<int>>.empty(),
    );

Future<String> _body(Response response) async => utf8.decode(await response.body!.bytes());

void main() {
  final List<Directory> sites = <Directory>[];
  Directory site(String shell) => _site(shell)..let(sites.add);

  setUp(dvPurgeRenderedPages);
  tearDown(() {
    DVOffSwitches.current = DVOffSwitches.none;
    for (final Directory dir in sites) {
      dir.deleteSync(recursive: true);
    }
    sites.clear();
  });

  test('nothing off: no meta tag in any page', () async {
    final Directory root = site(_plainShell);
    for (final String path in <String>['/', '/pricing', '/missing', '/private']) {
      expect(await _body(await handleSsrFallback(_get(path), root.path)), isNot(contains('dartvel-off')));
    }
  });

  test('page-scroll-button: every page tells the client, the shell too', () async {
    final Directory root = site(_plainShell);
    DVOffSwitches.current = DVOffSwitches.parse('page-scroll-button');
    for (final String path in <String>['/', '/pricing', '/missing', '/private']) {
      final String page = await _body(await handleSsrFallback(_get(path), root.path));
      expect(DVOffSwitches.fromPage(page).isOff(DVOffSwitches.pageScrollButton), isTrue, reason: path);
    }
  });

  test('a site without a manifest (the prerendered shell) carries it as well', () async {
    final Directory root = site(_plainShell);
    File('${root.path}/dartvel_routes.json').deleteSync();
    DVOffSwitches.current = DVOffSwitches.parse('analytics');
    final String page = await _body(await handleSsrFallback(_get('/anything'), root.path));
    expect(DVOffSwitches.fromPage(page).isOff(DVOffSwitches.analytics), isTrue);
  });

  test('a server switch alone adds nothing for the client', () async {
    final Directory root = site(_plainShell);
    DVOffSwitches.current = DVOffSwitches.parse('cache-warm');
    expect(await _body(await handleSsrFallback(_get('/pricing'), root.path)), isNot(contains('dartvel-off')));
  });

  test('ssr-first: every page byte for byte what a non-SSR-first build serves', () async {
    final Directory ssrFirst = site(_ssrFirstShell());
    final Directory plain = site(_plainShell);
    for (final String path in <String>['/', '/pricing', '/missing', '/private']) {
      DVOffSwitches.current = DVOffSwitches.none;
      final String expected = await _body(await handleSsrFallback(_get(path), plain.path));
      final String before = await _body(await handleSsrFallback(_get(path), ssrFirst.path));
      expect(before, contains(dvSsrFirstMarker), reason: 'the site is SSR-first until switched off');
      dvPurgeRenderedPages();
      DVOffSwitches.current = DVOffSwitches.parse('ssr-first');
      final String off = await _body(await handleSsrFallback(_get(path), ssrFirst.path));
      expect(off, expected, reason: path);
      dvPurgeRenderedPages();
    }
  });

  test('an HTML file of the site asked for by name is served with the switches applied', () async {
    final Directory root = site(_ssrFirstShell());
    expect(await dvOffSwitchedSiteHtml(_get('/index.html'), root.path), isNull, reason: 'nothing off: the file as built');
    DVOffSwitches.current = DVOffSwitches.parse('ssr-first page-scroll-button');
    final Response? file = await dvOffSwitchedSiteHtml(_get('/index.html'), root.path);
    expect(file, isNotNull);
    final String page = await _body(file!);
    expect(page, isNot(contains(dvSsrFirstMarker)));
    expect(DVOffSwitches.fromPage(page).isOff(DVOffSwitches.pageScrollButton), isTrue);
    expect(await dvOffSwitchedSiteHtml(_get('/main.dart.js'), root.path), isNull);
  });

  test('the start-up log names what is off and every name it does not know', () {
    expect(dvOffSwitchesLog(DVOffSwitches.none), isEmpty);
    expect(dvOffSwitchesLog(DVOffSwitches.parse('ssr-first, page-scrol-button')), <String>[
      'dartvel: off switches (DARTVEL_OFF): ssr-first',
      'dartvel: DARTVEL_OFF names "page-scrol-button", which is not a switch; known: '
          'analytics, cache-warm, page-scroll-button, ssr-first, module:<id>',
    ]);
  });
}

extension<T> on T {
  void let(void Function(T) use) => use(this);
}
