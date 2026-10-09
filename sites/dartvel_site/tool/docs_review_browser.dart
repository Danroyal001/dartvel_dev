// Read-only local browser evidence. Run from the site after building and
// starting build/server: dart run tool/docs_review_browser.dart <base> <out>.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:puppeteer/puppeteer.dart';

Future<void> main(List<String> args) async {
  final String base = args[0];
  final Directory out = Directory(args[1])..createSync(recursive: true);
  final List<File> pages =
      Directory('lib/pages')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.readAsStringSync().contains('@DVPage('))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  final Map<String, String> routes = <String, String>{};
  for (final File f in pages) {
    String path = f.path
        .substring('lib/pages'.length)
        .replaceFirst(RegExp(r'\.dart$'), '');
    path = path.replaceFirst(RegExp(r'/index$'), '');
    routes[path.isEmpty ? '/' : path] = f.path;
  }
  final Browser browser = await puppeteer.connect(
    browserUrl:
        Platform.environment['DOCS_REVIEW_CDP'] ?? 'http://127.0.0.1:9334',
  );
  final Page page = await browser.newPage();
  final HttpClient client = HttpClient();
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  const Set<String> shots = <String>{
    '/docs/modules',
    '/docs/existing-native-apps',
    '/docs/adopting',
    '/docs/cache',
    '/docs/media-3d',
    '/docs/releases',
  };
  try {
    for (final MapEntry<String, String> route in routes.entries) {
      final String slug = route.key == '/'
          ? 'home'
          : route.key.substring(1).replaceAll('/', '-');
      final request = await client.getUrl(Uri.parse('$base${route.key}'));
      final response = await request.close();
      final String local = await response.transform(utf8.decoder).join();
      final ProcessResult liveResult = await Process.run('curl', <String>[
        '--silent',
        '--show-error',
        '--max-time',
        '30',
        '--resolve',
        'dartvel.dev:443:127.0.0.1',
        'https://dartvel.dev${route.key}',
      ]);
      final String live = liveResult.stdout as String;
      File('${out.path}/$slug.local.html').writeAsStringSync(local);
      File('${out.path}/$slug.live.html').writeAsStringSync(live);
      final ProcessResult diff = await Process.run('diff', <String>[
        '-u',
        '${out.path}/$slug.live.html',
        '${out.path}/$slug.local.html',
      ]);
      File('${out.path}/$slug.diff').writeAsStringSync(diff.stdout as String);
      final List<Map<String, Object?>> widths = <Map<String, Object?>>[];
      for (final int width in <int>[360, 768, 1440]) {
        await page.setViewport(DeviceViewport(width: width, height: 960));
        await page.goto('$base${route.key}', wait: Until.domContentLoaded);
        await Future<void>.delayed(const Duration(seconds: 2));
        // Enable Flutter semantics as an assistive client would.
        await page.evaluate<void>(r'''() => {
          const p = document.querySelector('flt-semantics-placeholder');
          if (p) p.click();
        }''');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final Map<String, dynamic> dom = await page
            .evaluate<Map<String, dynamic>>(r'''() => {
          const headings = [...document.querySelectorAll('h1,h2,h3,[role="heading"]')].map(e=>e.textContent.trim()).filter(Boolean);
          const links = [...document.querySelectorAll('a[href]')].length;
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let n, selected = '';
          while (n = walker.nextNode()) {
            if (n.textContent.trim().length < 12 || ['SCRIPT','STYLE'].includes(n.parentElement.tagName)) continue;
            const r = document.createRange(); r.selectNodeContents(n);
            const selection = getSelection(); selection.removeAllRanges(); selection.addRange(r);
            selected = selection.toString(); selection.removeAllRanges(); break;
          }
          return {headings, links, selected: selected.length > 0,
            overflow: document.documentElement.scrollWidth > innerWidth,
            findable: document.body.textContent.trim().length > 100};
        }''');
        await page.keyboard.press(Key.tab);
        final String focus = await page.evaluate<String>(
          '() => document.activeElement.tagName',
        );
        final ax = await page.session.send('Accessibility.getFullAXTree');
        final List<dynamic> nodes = ax['nodes'] as List<dynamic>;
        final int named = nodes
            .where(
              (dynamic n) =>
                  n['ignored'] != true &&
                  (n['name']?['value'] ?? '').toString().isNotEmpty,
            )
            .length;
        if (shots.contains(route.key) && width != 768) {
          File('${out.path}/$slug-$width.png')
              .writeAsBytesSync(await page.screenshot());
        }
        widths.add(<String, Object?>{
          'width': width,
          ...dom,
          'focusTag': focus,
          'namedAXNodes': named,
        });
      }
      results.add(<String, Object?>{
        'route': route.key,
        'source': route.value,
        'status': response.statusCode,
        'liveCurlExit': liveResult.exitCode,
        'sameHTML': local == live,
        'localSHA256': sha256.convert(utf8.encode(local)).toString(),
        'liveSHA256': sha256.convert(utf8.encode(live)).toString(),
        'widths': widths,
      });
      File(
        '${out.path}/results.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
      stdout.writeln(
        '${route.key}: HTTP ${response.statusCode}; widths checked',
      );
    }
  } finally {
    await page.close();
    browser.disconnect();
    client.close(force: true);
  }
}
