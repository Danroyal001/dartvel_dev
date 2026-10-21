// Checks drag and drop in a real browser against a running web-server build
// of the scratch page in docs/testing/drag_drop_page.dart.txt.
//
//   dart run tool/verify_drag_drop.dart <url> <output-dir>
//
// Launches and closes its own headless Chrome; it never connects to a shared
// one. Drags go through Chrome's own drag pipeline (CDP
// Input.dispatchDragEvent), so the page receives the dragenter, dragover and
// drop events, and the DataTransfer, that a drag from another application
// produces -- a real file read from disk, a link, plain text. Dragging out is
// checked with Input.setInterceptDrags: a real mouse press and move on the
// draggable starts the browser's drag, Chrome reports what it carries, and
// that is dropped back onto the drop zone. It is not a drag from a second
// operating-system application, which no headless browser can make.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';

const String zoneName = 'Drop a file, link or text here';
const String draggableName = 'Drag this link out';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: verify_drag_drop.dart <url> <output-dir>');
    exit(64);
  }
  final Directory out = Directory(args[1])..createSync(recursive: true);
  final File dropped = File('${out.path}/drop.txt')..writeAsStringSync('dropped bytes');
  final Browser browser = await puppeteer.launch(
    executablePath: '/opt/google/chrome/chrome',
    headless: true,
    args: <String>['--no-sandbox', '--disable-dev-shm-usage'],
  );
  final List<Map<String, Object?>> checks = <Map<String, Object?>>[];
  var failed = false;
  void check(String name, bool ok, [Object? detail]) {
    checks.add(<String, Object?>{'check': name, 'ok': ok, if (detail != null) 'detail': detail});
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $name${detail == null ? '' : '  $detail'}');
    if (!ok) failed = true;
  }

  try {
    final Page page = await browser.newPage();
    page.onConsole.listen((ConsoleMessage message) => stdout.writeln('console: ${message.text}'));
    final cdp = page.session;
    for (final String theme in <String>['light', 'dark']) {
      await cdp.send('Emulation.setEmulatedMedia', <String, Object?>{
        'features': <Object?>[
          <String, Object?>{'name': 'prefers-color-scheme', 'value': theme},
        ],
      });
      for (final int width in <int>[390, 1024, 1366]) {
        final String at = '$width $theme';
        await page.setViewport(DeviceViewport(width: width, height: 900));
        await page.goto(args[0], wait: Until.networkIdle);
        await page.waitForSelector('flutter-view', timeout: const Duration(seconds: 60));
        await page.evaluate<void>("() => document.querySelector('flt-semantics-placeholder')?.click()");
        await page.waitForFunction(
          '(name) => [...document.querySelectorAll("flt-semantics")].some((e) => (e.getAttribute("aria-label") || e.textContent || "").includes(name))',
          args: <Object?>[zoneName],
          timeout: const Duration(seconds: 60),
        );

        Future<Map<String, dynamic>> rectOf(String name) async =>
            (await page.evaluate<Map<String, dynamic>>(
              '''(name) => {
                const all = [...document.querySelectorAll('flt-semantics')]
                  .filter((e) => (e.getAttribute('aria-label') || e.textContent || '').includes(name));
                all.sort((a, b) => a.getBoundingClientRect().width * a.getBoundingClientRect().height
                  - b.getBoundingClientRect().width * b.getBoundingClientRect().height);
                const r = all[0].getBoundingClientRect();
                return {x: r.x + r.width / 2, y: r.y + r.height / 2};
              }''',
              args: <Object?>[name],
            ));

        final Map<String, dynamic> zone = await rectOf(zoneName);
        Future<bool> bodyHas(String needle) async {
          try {
            await page.waitForFunction(
              '(needle) => document.body.innerText.includes(needle) || [...document.querySelectorAll("flt-semantics")].some((e) => (e.getAttribute("aria-label") || e.textContent || "").includes(needle))',
              args: <Object?>[needle],
              timeout: const Duration(seconds: 10),
            );
            return true;
          } on Object {
            return false;
          }
        }

        Future<void> drag(Map<String, Object?> data, {bool expectHover = false}) async {
          final Map<String, Object?> payload = <String, Object?>{'dragOperationsMask': 1, ...data};
          for (final String type in <String>['dragEnter', 'dragOver']) {
            await cdp.send('Input.dispatchDragEvent', <String, Object?>{
              'type': type,
              'x': zone['x'],
              'y': zone['y'],
              'data': payload,
            });
          }
          if (expectHover) check('$at: hovering a drag over the zone tells it', await bodyHas('Hover: Hovering'));
          await cdp.send('Input.dispatchDragEvent', <String, Object?>{
            'type': 'drop',
            'x': zone['x'],
            'y': zone['y'],
            'data': payload,
          });
        }

        await drag(<String, Object?>{
          'items': <Object?>[],
          'files': <String>[dropped.absolute.path],
        }, expectHover: true);
        check('$at: a file from disk reaches .dropTarget() with its bytes',
            await bodyHas('"name":"drop.txt","type":"text/plain","bytes":"dropped bytes"'));
        check('$at: the zone stops hovering after the drop', await bodyHas('Hover: Not hovering'));

        await drag(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{'mimeType': 'text/uri-list', 'data': '# comment\r\nhttps://dartvel.dev/docs'},
            <String, Object?>{'mimeType': 'text/plain', 'data': 'https://dartvel.dev/docs'},
          ],
        });
        check('$at: a link arrives as a link, not as text',
            await bodyHas('"urls":["https://dartvel.dev/docs"],"text":null'));

        await drag(<String, Object?>{
          'items': <Object?>[
            <String, Object?>{'mimeType': 'text/plain', 'data': 'browser text payload'},
          ],
        });
        check('$at: plain text arrives as text', await bodyHas('"text":"browser text payload"'));

        // Dragging out: a real press and move on the draggable.
        await cdp.send('Input.setInterceptDrags', <String, Object?>{'enabled': true});
        final Completer<Map<String, dynamic>> intercepted = Completer<Map<String, dynamic>>();
        final StreamSubscription<Object?> listening = cdp.onEvent.listen((event) {
          if (event.name == 'Input.dragIntercepted' && !intercepted.isCompleted) {
            intercepted.complete(event.parameters);
          }
        });
        // Found the way a mouse finds it: moving down the page until the
        // draggable arms itself (the page becomes draggable under the mouse).
        Map<String, dynamic>? source;
        for (var y = 0; y < 900 && source == null; y += 6) {
          await page.mouse.move(Point<num>(60, y));
          if ((await page.evaluate<bool>("() => document.querySelector('flutter-view').draggable")) == true) {
            source = <String, dynamic>{'x': 60, 'y': y + 3};
          }
        }
        check('$at: a mouse over the draggable arms it before any press', source != null, source);
        source ??= await rectOf(draggableName);
        await page.mouse.move(Point<num>(source['x'] as num, source['y'] as num));
        await page.mouse.down();
        for (var step = 1; step <= 6; step++) {
          await page.mouse.move(Point<num>((source['x'] as num) + step * 8, (source['y'] as num) + step * 4));
        }
        Map<String, dynamic>? carried;
        try {
          carried = await intercepted.future.timeout(const Duration(seconds: 5));
        } on TimeoutException {
          carried = null;
        }
        await listening.cancel();
        final Map<String, dynamic>? data = carried?['data'] as Map<String, dynamic>?;
        final List<Object?> items = (data?['items'] as List<Object?>?) ?? const <Object?>[];
        final String carriedJson = jsonEncode(items);
        check('$at: pressing and moving the draggable starts the browser drag with its link and text',
            carriedJson.contains('https://dartvel.dev/docs/devices') && carriedJson.contains('Dartvel drag payload'),
            carriedJson);
        await page.mouse.up();
        await cdp.send('Input.setInterceptDrags', <String, Object?>{'enabled': false});
        if (data != null) {
          await drag(Map<String, Object?>.from(data));
          check('$at: what the draggable carried drops onto the zone',
              await bodyHas('"urls":["https://dartvel.dev/docs/devices"],"text":"Dartvel drag payload"'));
        }

        // The page is still a document.
        // Find-in-page reaches every word on the page, the drop zone's and the
        // draggable's included.
        final Map<String, dynamic> document = (await page.evaluate<Map<String, dynamic>>('''(words) => {
          const found = {};
          for (const word of words) {
            found[word] = window.find(word);
            getSelection().removeAllRanges();
          }
          return {found, overflow: document.documentElement.scrollWidth > innerWidth};
        }''', args: <Object?>[<String>['Drag and drop verification', zoneName, draggableName, 'Choose files instead']]));
        check('$at: find-in-page finds every word, drop zone and draggable included',
            (document['found'] as Map<String, dynamic>).values.every((Object? found) => found == true), document['found']);
        check('$at: no horizontal scroll', document['overflow'] == false);

        await page.mouse.move(Point<num>(zone['x'] as num, zone['y'] as num));
        await Future<void>.delayed(const Duration(milliseconds: 900));
        File('${out.path}/drag-drop-$width-$theme-hover.png').writeAsBytesSync(await page.screenshot());
        await page.mouse.move(const Point<num>(1, 1));

        final Map<String, dynamic> tree = await cdp.send('Accessibility.getFullAXTree');
        final List<Map<String, dynamic>> nodes = <Map<String, dynamic>>[
          for (final Object? node in tree['nodes'] as List<Object?>)
            if (node is Map && node['ignored'] != true) Map<String, dynamic>.from(node),
        ];
        String nameOf(Map<String, dynamic> node) => '${(node['name'] as Map?)?['value'] ?? ''}';
        String roleOf(Map<String, dynamic> node) => '${(node['role'] as Map?)?['value'] ?? ''}';
        check('$at: the drop zone is named for a screen reader',
            nodes.any((Map<String, dynamic> node) => nameOf(node).contains(zoneName)));
        check('$at: the draggable is named for a screen reader',
            nodes.any((Map<String, dynamic> node) => nameOf(node).contains(draggableName)));
        check('$at: the heading is a heading',
            nodes.any((Map<String, dynamic> node) => roleOf(node) == 'heading' && nameOf(node).contains('Drag and drop verification')));

        final List<String> tabbed = <String>[];
        for (var press = 0; press < 4; press++) {
          await page.keyboard.press(Key.tab);
          tabbed.add((await page.evaluate<String>(
              '() => (document.activeElement.getAttribute("aria-label") || document.activeElement.textContent || document.activeElement.tagName).trim()')));
        }
        check('$at: Tab reaches the "Choose files instead" control', tabbed.any((String name) => name.contains('Choose files instead')), tabbed);
        File('${out.path}/drag-drop-$width-$theme.png').writeAsBytesSync(await page.screenshot());
      }
    }
  } finally {
    File('${out.path}/checks.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(checks)}\n');
    await browser.close();
  }
  stdout.writeln(failed ? 'Some checks failed.' : 'All ${checks.length} checks passed.');
  exit(failed ? 1 : 0);
}
