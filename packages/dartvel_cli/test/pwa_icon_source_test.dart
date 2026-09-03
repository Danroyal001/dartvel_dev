// Where dartvel build web finds the icon it generates the PWA set from.
//
// Chrome refuses to install a PWA without 192 and 512 icons, and until now
// the manifest named four files nothing produced. The codec exists; this is
// the resolution that decides whether there is anything to feed it, and it
// has to be silent-by-default in the right direction: a project with no icon
// anywhere gets no icons and a plain message, not a build failure and not a
// generated placeholder that ships to a store.
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('dv_icon_src_'));
  tearDown(() => root.deleteSync(recursive: true));

  File put(String rel) => File('${root.path}/$rel')
    ..createSync(recursive: true)
    ..writeAsBytesSync(dvPngEncode(DVRgbaImage(2, 2)));

  group('resolving the source', () {
    test('a configured path wins', () {
      put('branding/logo.png');
      put('web/icon.png');
      final File? found = dvPwaIconSource(root.path,
          <Object?, Object?>{'icon': 'branding/logo.png'});
      expect(found?.path, endsWith('branding/logo.png'));
    });

    test('web/icon.png is the convention when nothing is configured', () {
      put('web/icon.png');
      put('assets/icon.png');
      expect(dvPwaIconSource(root.path, const <Object?, Object?>{})?.path,
          endsWith('web/icon.png'));
    });

    test('then assets/icon.png', () {
      put('assets/icon.png');
      expect(dvPwaIconSource(root.path, const <Object?, Object?>{})?.path,
          endsWith('assets/icon.png'));
    });

    test('nothing anywhere is null, not an exception', () {
      expect(dvPwaIconSource(root.path, const <Object?, Object?>{}), isNull);
    });

    test('a configured path that does not exist is an error, not a fallback',
        () {
      // Falling back to web/icon.png would quietly ship a different image
      // from the one the project named.
      put('web/icon.png');
      expect(
        () => dvPwaIconSource(root.path, <Object?, Object?>{'icon': 'nope.png'}),
        throwsA(isA<DVPngError>()
            .having((DVPngError e) => e.message, 'message', contains('nope.png'))),
      );
    });
  });

  group('the manifest colour', () {
    test('#RRGGBB becomes opaque ARGB', () {
      expect(dvHexToArgb('#112233'), 0xFF112233);
      expect(dvHexToArgb('112233'), 0xFF112233);
    });

    test('#RGB expands', () {
      expect(dvHexToArgb('#abc'), 0xFFAABBCC);
    });

    test('something that is not a colour falls back to white, and says so',
        () {
      // The manifest already tolerates a bad colour; the icon background
      // should not be the one place it becomes fatal.
      expect(dvHexToArgb('blue'), 0xFFFFFFFF);
      expect(dvHexToArgb(''), 0xFFFFFFFF);
    });
  });
}
