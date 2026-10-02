// What each platform's drag and drop hands over, recorded, and the drop it
// becomes. The shapes are the ones the bindings produce: the Android bridge's
// JSON, a browser's DataTransfer, the iOS bridge's JSON.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/android/android_drag_drop_shapes.dart';
import 'package:dartvel_flutter/src/platform/ios/ios_drag_drop_shapes.dart';
import 'package:dartvel_flutter/src/platform/web/web_drag_drop_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android', () {
    test('a photo dragged from Files in split screen', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvAndroidDropMap(<String, Object?>{
        'kind': 'drop',
        'x': 540.0,
        'y': 1200.0,
        'items': <Object?>[
          <String, Object?>{
            'uri': 'content://com.android.providers.media.documents/document/image%3A42',
            'mimeType': 'image/jpeg',
            'name': 'IMG_0042.jpg',
            'size': 2048,
          },
        ],
      }, devicePixelRatio: 2.7));
      final DVIncomingFile file = event.files.single;
      expect(file.name, 'IMG_0042.jpg');
      expect(file.mimeType, 'image/jpeg');
      expect(file.size, 2048);
      expect(file.uri!.scheme, 'content');
      expect(event.x, closeTo(200, 0.01), reason: 'physical pixels / ratio');
      expect(event.y, closeTo(444.44, 0.01));
    });

    test('a link dragged from Chrome is a link, not text', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvAndroidDropMap(<String, Object?>{
        'kind': 'drop', 'x': 0, 'y': 0,
        'items': <Object?>[<String, Object?>{'text': 'https://dartvel.dev/docs'}],
      }, devicePixelRatio: 1));
      expect(event.urls, <Uri>[Uri.parse('https://dartvel.dev/docs')]);
      expect(event.text, isNull);
    });

    test('text from Keep, and several items joined', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvAndroidDropMap(<String, Object?>{
        'kind': 'drop', 'x': 0, 'y': 0,
        'items': <Object?>[
          <String, Object?>{'text': 'first line'},
          <String, Object?>{'text': 'second line'},
        ],
      }, devicePixelRatio: 1));
      expect(event.text, 'first line\nsecond line');
      expect(event.urls, isEmpty);
    });

    test('a content URI the provider would not name still arrives, named by its path', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvAndroidDropMap(<String, Object?>{
        'kind': 'drop', 'x': 0, 'y': 0,
        'items': <Object?>[<String, Object?>{'uri': 'content://other.app/files/report.pdf'}],
      }, devicePixelRatio: 1));
      expect(event.files.single.name, 'report.pdf');
      expect(event.files.single.mimeType, 'application/pdf');
    });

    test('a non-content URI is a link', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvAndroidDropMap(<String, Object?>{
        'kind': 'drop', 'x': 0, 'y': 0,
        'items': <Object?>[<String, Object?>{'uri': 'https://example.com/a'}],
      }, devicePixelRatio: 1));
      expect(event.files, isEmpty);
      expect(event.urls.single.host, 'example.com');
    });
  });

  group('iOS and iPadOS', () {
    test('a file from Files in Split View, copied by the bridge before the drop returns', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvIosDropMap(<String, Object?>{
        'kind': 'drop',
        'x': 300.5,
        'y': 120.0,
        'items': <Object?>[
          <String, Object?>{
            'path': '/private/var/mobile/Containers/Data/Application/X/tmp/dartvel-drops/1/Budget.xlsx',
            'name': 'Budget.xlsx',
            'uti': 'org.openxmlformats.spreadsheetml.sheet',
            'mimeType': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          },
          <String, Object?>{'url': 'https://apple.com'},
          <String, Object?>{'text': 'a note'},
        ],
      }));
      expect(event.files.single.name, 'Budget.xlsx');
      expect(event.paths.single, endsWith('/Budget.xlsx'));
      expect(event.urls.single.host, 'apple.com');
      expect(event.text, 'a note');
      expect(event.x, 300.5, reason: 'UIKit points are already logical');
    });

    test('a file:// URL is a file, not a link', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvIosDropMap(<String, Object?>{
        'kind': 'drop', 'x': 0, 'y': 0,
        'items': <Object?>[<String, Object?>{'url': 'file:///tmp/dartvel-drops/2/a.png'}],
      }));
      expect(event.urls, isEmpty);
      expect(event.paths.single, '/tmp/dartvel-drops/2/a.png');
    });
  });

  group('web', () {
    test('a link dragged from another tab: uri-list and the same URL as text', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvWebDropMap(
        files: const <Map<String, Object?>>[],
        uriList: '# from a tab\r\nhttps://dartvel.dev/\r\n',
        text: 'https://dartvel.dev/',
        x: 10,
        y: 20,
      ));
      expect(event.urls, <Uri>[Uri.parse('https://dartvel.dev/')]);
      expect(event.text, isNull, reason: 'the text/plain copy of a link is the link');
      expect(event.position, const Offset(10, 20));
    });

    test('files from the desktop: names and types, no paths', () {
      final DVDropEvent event = DVDropEvent.fromMap(dvWebDropMap(
        files: const <Map<String, Object?>>[
          <String, Object?>{'name': 'a.png', 'mimeType': 'image/png', 'size': 10},
          <String, Object?>{'name': 'notes.md', 'mimeType': '', 'size': 3},
        ],
        uriList: '',
        text: '',
      ));
      expect(event.files.map((DVIncomingFile file) => file.mimeType), <String?>['image/png', 'text/markdown'],
          reason: 'an empty browser type falls back to the extension');
      expect(event.paths, isEmpty);
    });

    test('selected text', () {
      final DVDropEvent event = DVDropEvent.fromMap(
          dvWebDropMap(files: const <Map<String, Object?>>[], uriList: '', text: 'hello there'));
      expect(event.text, 'hello there');
      expect(event.urls, isEmpty);
    });
  });
}
