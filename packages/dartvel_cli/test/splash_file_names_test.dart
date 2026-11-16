// Studio draws the application's splash while its code loads, from the
// pictures the web splash wrote beside index.html. The file names are one
// constant each, so renaming one cannot leave Studio asking for a picture
// that is not there (audit finding 9).
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('the web splash writes its pictures under the shared names', () {
    final Directory root = Directory.systemTemp.createTempSync('dartvel_splash_names_');
    addTearDown(() => root.deleteSync(recursive: true));
    final DVRgbaImage image = DVRgbaImage(64, 64);
    File(p.join(root.path, 'splash.png')).writeAsBytesSync(dvPngEncode(image));
    File(p.join(root.path, 'splash-dark.png')).writeAsBytesSync(dvPngEncode(image));
    final Directory web = Directory(p.join(root.path, 'build', 'web'))..createSync(recursive: true);
    File(p.join(web.path, 'index.html')).writeAsStringSync('<html><head></head><body></body></html>');
    dvWriteWebSplash(
      web,
      DVSplash.fromConfig(<String, Object?>{
        'splash': <String, Object?>{'image': 'splash.png', 'darkImage': 'splash-dark.png'},
      }, root: root.path),
    );
    expect(File(p.join(web.path, dvWebSplashImage)).existsSync(), isTrue);
    expect(File(p.join(web.path, dvWebSplashDarkImage)).existsSync(), isTrue);
  });

  test('Studio\'s splash names them through the same constants, never as literals', () {
    final String generator = File('lib/src/generators/client_generator.dart').readAsStringSync();
    expect(generator, contains('dvWebSplashImage'));
    expect(generator, contains('dvWebSplashDarkImage'));
    expect(generator, isNot(contains("image: 'dartvel-splash.png'")));
    expect(generator, isNot(contains("darkImage: 'dartvel-splash-dark.png'")));
  });
}
