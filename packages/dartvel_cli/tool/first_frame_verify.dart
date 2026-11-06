/// Measures a locally built web-server binary, with its app scripts blocked
/// and with Flutter rendered. Run from the root after starting build/server:
/// dart run packages/dartvel_cli/tool/first_frame_verify.dart 18772 /tmp/first-frame-results
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/first_frame_capture.dart';
import 'package:puppeteer/puppeteer.dart';

Future<void> main(List<String> args) async {
  final int port = int.parse(args[0]);
  final Directory output = Directory(args[1])..createSync(recursive: true);
  final List<String> routes = args.length > 2
      ? args.sublist(2)
      : <String>['/', '/docs', '/pricing', '/docs/routing', '/cloud'];
  final Browser browser = await puppeteer.launch(
    executablePath: await dvChromeExecutable(),
    args: dvChromeLaunchArgs,
  );
  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  bool failed = false;
  try {
    for (final String route in routes) {
      for (final int width in <int>[390, 1366, 1920]) {
        for (final String scheme in <String>['light', 'dark']) {
          final int height = width < 700 ? 844 : 900;
          final String name =
              '${route == '/' ? 'index' : route.substring(1).replaceAll('/', '_')}-$width-$scheme';
          bool picture = false, find = false, removed = false;
          int? status;
          for (final bool app in <bool>[false, true]) {
            final Page page = await browser.newPage();
            try {
              await page.setViewport(.new(width: width, height: height));
              await dvEmulateColourScheme(page, scheme);
              await page.devTools.network.setBypassServiceWorker(true);
              await page.setCacheEnabled(false);
              await page.setRequestInterception(true);
              page.onRequest.listen((Request request) async {
                if (!app &&
                    RegExp(r'main\.dart|flutter_bootstrap|canvaskit|\.wasm')
                        .hasMatch(request.url)) {
                  await request.abort();
                } else {
                  await request.continueRequest();
                }
              });
              await page.evaluateOnNewDocument(
                'addEventListener("flutter-first-frame",()=>{window.dvVerifyFrame=true})',
              );
              final Response response = await page.goto(
                'http://127.0.0.1:$port$route',
                wait: .networkIdle,
                timeout: const .new(minutes: 2),
              );
              status = response.status;
              if (app) {
                await page.waitForFunction(
                  '()=>window.dvVerifyFrame===true',
                  timeout: const Duration(minutes: 2),
                );
                await Future<void>.delayed(const .new(milliseconds: 2500));
                removed = await page.evaluate<bool>(
                  '()=>document.getElementById("dv-first-frame")===null',
                );
              } else {
                picture = await page.evaluate<bool>(
                  '()=>{const f=document.getElementById("dv-first-frame");return !!f && getComputedStyle(f).display!=="none"}',
                );
                find = await page.evaluate<bool>('()=>window.find("Dartvel")');
                await page.evaluate<Object?>(
                  '()=>{getSelection().removeAllRanges();window.scrollTo(0,0)}',
                );
              }
              File('${output.path}/$name-$app.png')
                  .writeAsBytesSync(await page.screenshot());
            } finally {
              await page.close();
            }
          }
          final ProcessResult comparison = await Process.run(
            'compare',
            <String>[
              '-metric',
              'AE',
              '-fuzz',
              '10%',
              '${output.path}/$name-false.png',
              '${output.path}/$name-true.png',
              '${output.path}/$name-diff.png',
            ],
          );
          if (comparison.exitCode > 1) throw StateError('${comparison.stderr}');
          final int changed = num.parse(
            '${comparison.stderr}'.trim().split(RegExp(r'\s+')).first,
          ).round();
          final double percent = 100 * changed / (width * height);
          final row = <String, Object?>{
            'route': route,
            'width': width,
            'scheme': scheme,
            'status': status,
            'picture': picture,
            'find': find,
            'removed': removed,
            'changed': changed,
            'percent': percent,
          };
          results.add(row);
          stdout.writeln(jsonEncode(row));
          File('${output.path}/results.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(results),
          );
          failed |=
              status != 200 || !picture || !find || !removed || percent > 0.1;
        }
      }
    }
  } finally {
    await browser.close();
  }
  if (failed) exitCode = 1;
}
