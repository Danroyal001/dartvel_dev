// Measures how fast a Dartvel web build loads, with Lighthouse.
//
//   dart tool/web_vitals.dart https://dartvel.dev/ https://dartvel.dev/docs/ui
//   dart tool/web_vitals.dart --desktop https://dartvel.dev/
//
// Prints one markdown row per URL: time to first byte, first and largest
// contentful paint, time to interactive, total blocking time, the bytes the
// page transferred, and the bytes of the pieces a Flutter web page is made
// of -- the compiled app, the renderer, the fonts. docs/web-performance.md
// keeps the rows from before and after each change.
//
// Lighthouse runs from npx (LIGHTHOUSE names another), in headless Chrome.
// Only dart: libraries are imported, so this runs with `dart tool/...` and
// no package resolution.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final bool desktop = args.contains('--desktop');
  final List<String> urls =
      args.where((String a) => !a.startsWith('--')).toList();
  if (urls.isEmpty) {
    stderr.writeln('usage: dart tool/web_vitals.dart [--desktop] <url>...');
    exitCode = 2;
    return;
  }
  final String lighthouse = Platform.environment['LIGHTHOUSE'] ?? 'npx';
  stdout.writeln('| URL | Profile | TTFB | FCP | LCP | TTI | TBT | Transferred | App JS/Wasm | Renderer | Fonts |');
  stdout.writeln('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final String url in urls) {
    final Directory tmp = Directory.systemTemp.createTempSync('dv_vitals_');
    final String out = '${tmp.path}/report.json';
    final ProcessResult run = await Process.run(lighthouse, <String>[
      if (lighthouse == 'npx') ...<String>['--yes', 'lighthouse@12'],
      url,
      '--output=json',
      '--output-path=$out',
      '--quiet',
      '--only-categories=performance',
      if (desktop) '--preset=desktop',
      '--chrome-flags=--headless=new --no-sandbox --disable-gpu',
    ]);
    if (run.exitCode != 0 || !File(out).existsSync()) {
      stderr.writeln('lighthouse failed for $url: ${run.stderr}');
      tmp.deleteSync(recursive: true);
      exitCode = 1;
      continue;
    }
    final Map<String, Object?> report =
        jsonDecode(File(out).readAsStringSync()) as Map<String, Object?>;
    tmp.deleteSync(recursive: true);
    stdout.writeln(row(url, desktop ? 'desktop' : 'mobile', report));
  }
}

/// One table row from a Lighthouse [report].
String row(String url, String profile, Map<String, Object?> report) {
  final Map<String, Object?> audits = report['audits']! as Map<String, Object?>;
  num value(String id) =>
      ((audits[id] as Map<String, Object?>?)?['numericValue'] as num?) ?? 0;
  String ms(String id) => '${value(id).round()} ms';

  int app = 0, renderer = 0, fonts = 0, total = 0;
  final Object? details = (audits['network-requests']
      as Map<String, Object?>?)?['details'];
  final List<Object?> items = details is Map<String, Object?>
      ? (details['items'] as List<Object?>? ?? const <Object?>[])
      : const <Object?>[];
  for (final Object? item in items) {
    final Map<String, Object?> r = item! as Map<String, Object?>;
    final String u = '${r['url']}';
    final int bytes = (r['transferSize'] as num?)?.toInt() ?? 0;
    total += bytes;
    if (u.contains('canvaskit') || u.contains('skwasm')) {
      renderer += bytes;
    } else if (u.endsWith('main.dart.js') ||
        u.endsWith('main.dart.wasm') ||
        u.endsWith('main.dart.mjs') ||
        RegExp(r'main\.dart\.js_\d+\.part\.js$').hasMatch(u)) {
      app += bytes;
    } else if (RegExp(r'\.(woff2?|ttf|otf)(\?|$)').hasMatch(u) ||
        u.contains('fonts.gstatic.com')) {
      fonts += bytes;
    }
  }
  String kb(int b) => '${(b / 1024).round()} KB';
  return '| $url | $profile | ${ms('server-response-time')} | '
      '${ms('first-contentful-paint')} | ${ms('largest-contentful-paint')} | '
      '${ms('interactive')} | ${ms('total-blocking-time')} | ${kb(total)} | '
      '${kb(app)} | ${kb(renderer)} | ${kb(fonts)} |';
}
