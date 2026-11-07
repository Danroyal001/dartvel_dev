import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/first_frame_capture.dart';
import 'package:dartvel_core/dartvel.dart' show DVFirstFrame, dvFirstFrameHtml;
import 'package:path/path.dart' as p;
import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:image/image.dart' as img;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

void main() {
  test('a pending Flutter view cannot cover the first-frame picture', () async {
    final browser = await puppeteer.launch(
      executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
    try {
      final page = await browser.newPage();
      await page.setViewport(const DeviceViewport(width: 390, height: 844));
      await page.setContent(dvFirstFrameHtml(const [
        DVFirstFrame(width: 390, dark: false, src: 'picture.png'),
      ]));
      // The picture shows only once the browser has it decoded; this one is
      // never served, so it stays hidden until it is marked as decoded.
      expect(await page.evaluate<String>('''()=>getComputedStyle(document.getElementById('dv-first-frame')).display'''),
          'none', reason: 'no picture before it has loaded');
      await page.evaluate<Object?>('''()=>{
        document.documentElement.classList.add('dv-ff-ready');
        document.getElementById('dv-first-frame').style.backgroundColor='blue';
        const view=document.createElement('flutter-view');
        view.style.cssText='position:absolute;inset:0;background:white';
        document.body.append(view);
      }''');
      expect(await page.evaluate<bool>('''()=>
        document.elementFromPoint(195,400).closest('#dv-first-frame')!==null
      '''), isTrue, reason: 'the picture stays above an unrendered canvas');
    } finally {
      await browser.close();
    }
  });

  test('a premature Flutter callback cannot remove the unrendered picture', () async {
    final browser = await puppeteer.launch(
      executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
    try {
      final page = await browser.newPage();
      await page.setContent(dvFirstFrameHtml(const [
        DVFirstFrame(width: 390, dark: false, src: 'picture.png'),
      ]));
      await page.evaluate<Object?>('''async()=>{
        dispatchEvent(new Event('flutter-first-frame'));
        await new Promise(requestAnimationFrame);
        await new Promise(requestAnimationFrame);
      }''');
      expect(await page.evaluate<bool>(
        '()=>document.getElementById("dv-first-frame")!==null'), isTrue,
        reason: 'Flutter emits its callback even while engine rendering is deferred');
      await page.evaluate<Object?>(
        '()=>dispatchEvent(new Event("dartvel-first-frame"))');
      await page.waitForFunction(
        '()=>document.getElementById("dv-first-frame")===null');
    } finally {
      await browser.close();
    }
  });

  test('captured pixels survive encoding without changing the app', () async {
    final Browser browser = await puppeteer.launch(
      executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
    final Directory root = Directory.systemTemp.createTempSync('dv_ff_pixels_');
    try {
      final Page page = await browser.newPage();
      await page.setViewport(const DeviceViewport(width: 390, height: 844));
      // Fine edges and saturated colours expose WebP chroma subsampling.
      await page.setContent('''<style>body{margin:0}</style><canvas width="390" height="844"></canvas>
        <script>const c=document.querySelector('canvas').getContext('2d');
        for(let y=0;y<844;y++)for(let x=0;x<390;x++){
          c.fillStyle='rgb('+((x*37+y*13)%256)+','+((x*11)%256)+','+((y*29)%256)+')';
          c.fillRect(x,y,1,1);
        }</script>''');
      final img.Image expected = img.decodePng(await page.screenshot())!;
      await dvCaptureFirstFrames(page, projectRoot: root.path, route: '/', widths: <int>[390]);
      final List<DVFirstFrame> frames = dvPublishFirstFrames(
        root: root.path, route: '/', webRoot: p.join(root.path, 'web'));
      final img.Image actual = img.decodeImage(
        File(p.join(root.path, 'web', frames.first.src)).readAsBytesSync())!;
      int changed = 0;
      for (int y = 0; y < expected.height; y++) {
        for (int x = 0; x < expected.width; x++) {
          final a = expected.getPixel(x, y);
          final b = actual.getPixel(x, y);
          if (a.r != b.r || a.g != b.g || a.b != b.b) changed++;
        }
      }
      expect(changed, 0, reason: 'a first-frame picture must preserve every pixel');
    } finally {
      await browser.close();
      root.deleteSync(recursive: true);
    }
  });

  group('dartvel.web.firstFrame', () {
    test('captures the common phone and desktop widths unless told otherwise', () {
      expect(dvFirstFrameWidths(null), dvDefaultFirstFrameWidths);
      expect(dvDefaultFirstFrameWidths, containsAll(<int>[390, 1366, 1920]));
    });

    test('takes the widths it is given, sorted, once each', () {
      expect(dvFirstFrameWidths(<String, Object?>{'widths': <Object?>[1440, 390, 390, '412']}),
          <int>[390, 412, 1440]);
    });

    test('false turns it off', () {
      expect(dvFirstFrameWidths(false), isEmpty);
      expect(dvFirstFrameWidths(<String, Object?>{'enabled': false}), isEmpty);
    });

    test('a width that is not a window width is refused', () {
      expect(() => dvFirstFrameWidths(<String, Object?>{'widths': <Object?>[0]}), throwsFormatException);
      expect(() => dvFirstFrameWidths(<String, Object?>{'widths': <Object?>['wide']}), throwsFormatException);
    });
  });

  group('publishing a capture into the site', () {
    late Directory root;
    late Directory web;
    setUp(() {
      root = Directory.systemTemp.createTempSync('dv_ff_');
      web = Directory(p.join(root.path, 'build', 'web'))..createSync(recursive: true);
    });
    tearDown(() => root.deleteSync(recursive: true));

    void capture(String route, List<Map<String, Object?>> frames, Map<String, List<int>> pictures) {
      final Directory dir = Directory(dvFirstFrameDirFor(root.path, route))..createSync(recursive: true);
      pictures.forEach((String name, List<int> bytes) => File(p.join(dir.path, name)).writeAsBytesSync(bytes));
      File(dvFirstFramePathFor(root.path, route)).writeAsStringSync(jsonEncode(frames));
    }

    test('copies each picture beside the site under a name that changes with it', () {
      capture('/docs', <Map<String, Object?>>[
        <String, Object?>{'width': 390, 'dark': false, 'file': '390-light.webp', 'texts': <Object?>[
          <String, Object?>{'text': 'Docs', 'left': 1, 'top': 2, 'width': 3, 'height': 4},
        ]},
      ], <String, List<int>>{'390-light.webp': <int>[1, 2, 3]});
      final List<DVFirstFrame> frames = dvPublishFirstFrames(root: root.path, route: '/docs', webRoot: web.path);
      expect(frames, hasLength(1));
      expect(frames.single.src, startsWith('dv-first-frame/docs-390-light-'));
      expect(frames.single.src, endsWith('.webp'));
      expect(File(p.join(web.path, frames.single.src)).readAsBytesSync(), <int>[1, 2, 3]);
      expect(frames.single.texts.single.text, 'Docs');

      // A new picture is a new name, so a browser holding the old one fetches it.
      capture('/docs', <Map<String, Object?>>[
        <String, Object?>{'width': 390, 'dark': false, 'file': '390-light.webp', 'texts': <Object?>[]},
      ], <String, List<int>>{'390-light.webp': <int>[9, 9]});
      final String next = dvPublishFirstFrames(root: root.path, route: '/docs', webRoot: web.path).single.src;
      expect(next, isNot(frames.single.src));
    });

    test('a route with no capture, or a picture gone missing, publishes nothing for it', () {
      expect(dvPublishFirstFrames(root: root.path, route: '/none', webRoot: web.path), isEmpty);
      capture('/gone', <Map<String, Object?>>[
        <String, Object?>{'width': 390, 'dark': false, 'file': 'missing.webp', 'texts': <Object?>[]},
      ], <String, List<int>>{});
      expect(dvPublishFirstFrames(root: root.path, route: '/gone', webRoot: web.path), isEmpty);
    });

    test('the home page is named index', () {
      capture('/', <Map<String, Object?>>[
        <String, Object?>{'width': 1366, 'dark': true, 'file': '1366-dark.webp', 'texts': <Object?>[]},
      ], <String, List<int>>{'1366-dark.webp': <int>[7]});
      expect(dvPublishFirstFrames(root: root.path, route: '/', webRoot: web.path).single.src,
          startsWith('dv-first-frame/index-1366-dark-'));
    });
  });
}
