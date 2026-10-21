import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:puppeteer/protocol/emulation.dart' as cdp;
import 'package:dartvel_cli/src/build/chrome_launch.dart';

// Run from dartvel_cli after building a local server. This starts its own
// ephemeral browser and server, then closes both; it never uses a shared CDP session.
Future<void> main(List<String> args) async {
  if (args.length != 3 || !['scratch', 'docs'].contains(args[1])) {
    throw ArgumentError(
      'Usage: <server-binary> <scratch|docs> <output-directory>',
    );
  }
  final binary = args[0];
  final mode = args[1];
  final out = Directory(args[2])..createSync(recursive: true);
  final data = Directory.systemTemp.createTempSync('dv_browser_data');
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reservation.port;
  await reservation.close();
  final server = await Process.start(
    binary,
    [],
    workingDirectory: data.path,
    environment: {
      ...Platform.environment,
      'DARTVEL_PORT': '$port',
      'DARTVEL_HOST': '127.0.0.1',
      'DARTVEL_DATA_DIR': data.path,
      'DATABASE_URL': 'sqlite://${data.path}/app.sqlite',
    },
  );
  final log = File('${out.path}/server.log').openWrite();
  final stdoutSub = server.stdout.listen(log.add);
  final stderrSub = server.stderr.listen(log.add);
  Browser? browser;
  try {
    final client = HttpClient();
    bool ready = false;
    for (var i = 0; i < 100; i++) {
      try {
        final response = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/'),
        )).close();
        await response.drain<void>();
        if (response.statusCode == 200) {
          ready = true;
          break;
        }
      } on Object {
        // Retry while the local server starts.
      }
      await Future<void>.delayed(const .new(milliseconds: 300));
    }
    client.close(force: true);
    if (!ready) throw StateError('Local binary did not become ready');
    browser = await puppeteer.launch(
      executablePath: await dvChromeExecutable(),
      headless: true,
      args: [...dvChromeLaunchArgs, '--enable-unsafe-swiftshader'],
    );
    final results = <Object?>[];
    final localTexts = <String, String>{};
    final routes = mode == 'scratch'
        ? {'/': 'Deterministic build fixture'}
        : {
            '/docs/native-access': 'File associations',
            '/docs/building': 'Repeat web builds',
          };
    for (final route in routes.entries) {
      for (final width in [360, 390, 1024, 1280, 1366]) {
        for (final scheme in ['light', 'dark']) {
          final page = await browser.newPage();
          try {
            await page.setViewport(DeviceViewport(width: width, height: 900));
            await page.devTools.emulation.setEmulatedMedia(
              features: [
                cdp.MediaFeature(name: 'prefers-color-scheme', value: scheme),
              ],
            );
            await page.setJavaScriptEnabled(false);
            await page.goto('http://127.0.0.1:$port${route.key}', wait: .load);
            final text = await page.evaluate<String>(
              '() => document.body.innerText',
            );
            localTexts[route.key] = text;
            if (!text.contains(route.value)) {
              throw StateError('Missing server text ${route.value}');
            }
            final found = await page.evaluate<bool>(
              'term => window.find(term)',
              args: [route.value],
            );
            if (!found) throw StateError('Native document find failed');
            final selected = await page.evaluate<String>(
              '() => window.getSelection().toString()',
            );
            if (selected.isEmpty) throw StateError('Selection failed');
            await page.evaluate(
              '() => window.getSelection().removeAllRanges()',
            );
            await page.keyboard.press(.tab);
            final focus = await page.evaluate<String>(
              '() => document.activeElement.tagName',
            );
            if (mode == 'docs' && (focus == 'BODY' || focus == 'HTML')) {
              throw StateError('Tab did not reach a document control');
            }
            final ax = await page.accessibility.snapshot();
            bool named(AXNode node) =>
                (node.name?.contains(route.value) ?? false) ||
                node.children.any(named);
            if (!named(ax)) {
              throw StateError('Missing text in accessibility tree');
            }
            if (mode == 'docs') {
              await page.evaluate(
                '(id) => document.getElementById(id)?.scrollIntoView()',
                args: [
                  route.key.endsWith('building')
                      ? 'build-cache'
                      : 'file-associations',
                ],
              );
            }
            final name = '${route.key.replaceAll('/', '_')}-$width-$scheme';
            File('${out.path}/$name.png').writeAsBytesSync(
              await page.screenshot(fullPage: mode == 'scratch'),
            );
            results.add({
              'route': route.key,
              'width': width,
              'scheme': scheme,
              'serverText': true,
              'nativeFind': found,
              'selection': true,
              'tabFocus': focus,
              'accessibility': true,
            });
          } finally {
            await page.close();
          }
        }
      }
    }
    if (mode == 'scratch') {
      final page = await browser.newPage();
      try {
        await page.evaluateOnNewDocument(r'''() => {
          Object.defineProperty(globalThis, 'launchQueue', {configurable:true,
            value:{setConsumer(fn){globalThis.__dvConsumer = fn;}}});
        }''');
        await page.goto('http://127.0.0.1:$port/', wait: .load);
        await page.waitForFunction(
          '() => typeof globalThis.__dvConsumer === "function"',
          timeout: const .new(seconds: 60),
        );
        await page.evaluate(r'''() => globalThis.__dvConsumer({files:[{
          getFile: async () => new File(['order bytes'], 'received.order', {type:'application/x-order'})
        }]})''');
        await page.evaluate(
          '() => document.querySelector("flt-semantics-placeholder")?.click()',
        );
        await page.waitForFunction(
          '() => document.body.textContent.includes("received.order: 11 bytes")',
          timeout: const .new(seconds: 60),
        );
        File('${out.path}/opened-file.png')
            .writeAsBytesSync(await page.screenshot());
        results.add({'launchQueueFileNameAndBytes': true});
      } finally {
        await page.close();
      }
    }
    if (mode == 'docs') {
      for (final route in routes.keys) {
        final page = await browser.newPage();
        try {
          await page.setJavaScriptEnabled(false);
          await page.goto('https://dartvel.dev$route', wait: .load);
          final live = await page.evaluate<String>(
            '() => document.body.innerText',
          );
          final key = route.split('/').last;
          File('${out.path}/$key-live.txt').writeAsStringSync(live);
          File('${out.path}/$key-local.txt')
              .writeAsStringSync(localTexts[route]!);
          results.add({
            'liveComparison': route,
            'liveTextBytes': live.length,
            'localTextBytes': localTexts[route]!.length,
          });
        } finally {
          await page.close();
        }
      }
    }
    File('${out.path}/results.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(results)}\n',
    );
    stdout.writeln('${results.length} browser checks passed');
  } finally {
    await browser?.close();
    server.kill(.sigterm);
    await server.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();
    await log.close();
    if (data.existsSync()) data.deleteSync(recursive: true);
  }
}
