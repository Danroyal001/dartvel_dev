import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/first_frame_capture.dart';
import 'package:dartvel_core/dartvel.dart' show DVFirstFrame;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
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
