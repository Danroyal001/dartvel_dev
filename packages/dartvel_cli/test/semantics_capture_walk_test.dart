// The semantics walker, in a browser, on markup shaped like Flutter's.
//
// Flutter wraps an app bar's title in a <header> landmark (AppBar marks its
// title as a header), and the heading sits inside it. The walker used to skip
// every element that was not an <a>, a <flt-semantics> or an <h1>..<h6>, and
// it skipped what was inside them too, so a page whose only level-1 heading
// was its app bar title was reported as having none.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/semantics_capture.dart';
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

late Browser browser;

List<Map<String, Object?>> flatten(List<Object?> nodes) => <Map<String, Object?>>[
      for (final Object? node in nodes) ...<Map<String, Object?>>[
        node! as Map<String, Object?>,
        ...flatten((node as Map<String, Object?>)['children']! as List<Object?>),
      ],
    ];

Future<List<Map<String, Object?>>> capture(String body) async {
  final Page page = await browser.newPage();
  await page.setContent('<!DOCTYPE html><html><body><flt-semantics-host>$body</flt-semantics-host></body></html>');
  final String tree = await page.evaluate<String>(dvSemanticsExtractScript);
  await page.close();
  return flatten(jsonDecode(tree) as List<Object?>);
}

void main() {
  setUpAll(() async {
    browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
  });
  tearDownAll(() => browser.close());

  test('a heading inside a header landmark is captured with its level', () async {
    final nodes = await capture(
        '<flt-semantics><flt-semantics><header><h1>Settings</h1></header></flt-semantics>'
        '<flt-semantics><h2>Appearance</h2></flt-semantics></flt-semantics>');
    expect(nodes.where((n) => n['level'] == 1).map((n) => n['label']), <Object?>['Settings']);
    expect(nodes.where((n) => n['level'] == 2).map((n) => n['label']), <Object?>['Appearance']);
  });

  test('links and headings inside nav and main are captured too', () async {
    final nodes = await capture(
        '<flt-semantics><nav><a href="/docs">Docs</a></nav><main><h1>Title</h1></main></flt-semantics>');
    expect(nodes.any((n) => n['href'] == '/docs' && n['label'] == 'Docs'), isTrue);
    expect(nodes.any((n) => n['level'] == 1 && n['label'] == 'Title'), isTrue);
  });

  test('a wrapper element adds no node of its own', () async {
    final nodes = await capture('<flt-semantics><header><h1>Only</h1></header></flt-semantics>');
    expect(nodes.where((n) => n['label'] == '' && n['level'] == null && n['href'] == null && (n['children']! as List).isEmpty), isEmpty);
    expect(nodes.where((n) => n['label'] == 'Only'), hasLength(1));
  });
}
