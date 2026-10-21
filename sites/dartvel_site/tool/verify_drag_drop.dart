import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';

Future<void> main(List<String> args) async {
  final browser = await puppeteer.launch(
    executablePath: '/opt/google/chrome/chrome',
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  );
  final out = Directory(args[1])..createSync(recursive: true);
  final checks = <Object?>[];
  try {
    final page = await browser.newPage();
    page.onConsole.listen(
      (message) => stdout.writeln('console: ${message.text}'),
    );
    for (final theme in ['light', 'dark']) {
      await page.session.send('Emulation.setEmulatedMedia', {
        'features': [
          {'name': 'prefers-color-scheme', 'value': theme},
        ],
      });
      for (final width in [360, 390, 1024, 1280, 1366]) {
        await page.setViewport(DeviceViewport(width: width, height: 960));
        await page.goto(args[0], wait: Until.networkIdle);
        await page.waitForSelector('flutter-view');
        await page.evaluate<void>(
          "() => document.querySelector('flt-semantics-placeholder')?.click()",
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        for (final kind in ['file', 'url', 'text']) {
          await page.evaluate<void>(
            '''(kind) => {
 const dt=new DataTransfer();
 if(kind==='file') dt.items.add(new File(['dropped bytes'], 'drop.txt', {type:'text/plain'}));
 if(kind==='url') {dt.setData('text/uri-list','# comment\\r\\nhttps://dartvel.dev/docs');dt.setData('text/plain','https://dartvel.dev/docs');}
 if(kind==='text') dt.setData('text/plain','browser text payload');
 const target=[...document.querySelectorAll('flt-semantics')].find(e=>e.textContent==='Drop a file, link or text here');
 const rect=target?.getBoundingClientRect();
 if(!rect) throw Error('Drop target semantics missing');
 const opts={dataTransfer:dt,clientX:rect.x+rect.width/2,clientY:rect.y+rect.height/2,bubbles:true,cancelable:true};
 window.dispatchEvent(new DragEvent('dragover',opts));
 window.dispatchEvent(new DragEvent('drop',opts));
 }''',
            args: [kind],
          );
          final needle = kind == 'file'
              ? '100,114,111,112,112,101,100,32,98,121,116,101,115'
              : kind == 'url'
              ? 'https://dartvel.dev/docs'
              : 'browser text payload';
          await page.waitForFunction(
            '(needle)=>document.body.innerText.includes(needle)',
            args: [needle],
          );
          checks.add({
            'width': width,
            'theme': theme,
            'kind': kind,
            'delivered': true,
          });
        }
        final doc = await page.evaluate<Map<String, dynamic>>('''() => {
 const found=window.find('Drag and drop verification');
 const selection=getSelection().toString().length>0;
 getSelection().removeAllRanges();
 return {find:found,selection,overflow:document.documentElement.scrollWidth>innerWidth};
 }''');
        await page.keyboard.press(Key.tab);
        final focus = await page.evaluate<String>('() => document.activeElement.tagName');
        final ax = await page.session.send('Accessibility.getFullAXTree');
        final names = (ax['nodes'] as List)
            .where(
              (n) =>
                  n['ignored'] != true &&
                  (n['name']?['value'] ?? '').toString().isNotEmpty,
            )
            .length;
        checks.add({
          'width': width,
          'theme': theme,
          ...doc,
          'namedAXNodes': names,
          'focusAfterTab': focus,
        });
        File('${out.path}/drag-drop-$width-$theme.png')
            .writeAsBytesSync(await page.screenshot());
        if (doc['find'] != true ||
            doc['selection'] != true ||
            doc['overflow'] == true ||
            names < 3 || focus == 'BODY')
          throw StateError('Document accessibility failed: $doc, $names nodes');
      }
    }
    File('${out.path}/checks.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(checks)}\n',
    );
  } finally {
    await browser.close();
  }
}
