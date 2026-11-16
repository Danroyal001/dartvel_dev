// The fonts and a route's modules are asked for the moment the app and its
// renderer have downloaded, and not before: on a slow line every byte the
// page asks for early is a byte main.dart.wasm waits behind.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/font_preloads.dart';
import 'package:dartvel_core/dartvel.dart' show dvWasmModulePreloads;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

late Browser browser;
late HttpServer server;
String html = '';

Future<int> _preloads(Page page) => page.evaluate<int>(
    '() => document.querySelectorAll(\'link[rel="preload"][as="fetch"]\').length');

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      request.response.headers.contentType = request.uri.path == '/'
          ? ContentType.html
          : ContentType('application', 'octet-stream');
      request.response
        ..write(request.uri.path == '/' ? html : 'x')
        ..close();
    });
    browser = await puppeteer.launch(
      executablePath: await dvChromeExecutable(),
      args: dvChromeLaunchArgs,
    );
    html = dvApplyFontPreloads(
      '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>t</title>'
      '${dvWasmModulePreloads(<String>['main.dart_module3.wasm'])}</head>'
      '<body></body></html>',
      <String>['assets/FontManifest.json', 'assets/fonts/a.woff2'],
    );
  });

  tearDownAll(() async {
    await browser.close();
    await server.close(force: true);
  });

  test('nothing before the app and the renderer, everything after both', () async {
    final Page page = await browser.newPage();
    await page.goto('http://127.0.0.1:${server.port}/', wait: Until.load);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await _preloads(page), 0);

    await page.evaluate<void>(
        '() => fetch("/main.dart.wasm?v=1").then(r => r.text())');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await _preloads(page), 0, reason: 'the renderer is still on its way');

    await page.evaluate<void>(
        '() => fetch("/canvaskit/skwasm.wasm").then(r => r.text())');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Two fonts' worth from the shell, one module from the route: this
    // Chrome runs the wasm app.
    expect(await _preloads(page), 3);
    await page.close();
  });
}
