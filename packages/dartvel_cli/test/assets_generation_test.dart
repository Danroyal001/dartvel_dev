// Bundled assets are typed: `DVAsset.logoSmall`, never 'assets/logo-small.png'.
//
// A string path is checked by nothing: a renamed file, a typo or a missing
// entry in pubspec.yaml all fail at run time, on a device, as a blank box.
// The generator reads what the project bundles and writes an enum, naming
// each from its file and taking its kind from the extension.
import 'dart:io';

import 'package:dartvel_cli/src/generators/assets_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory project;

void write(String path, String content) {
  final File file = File(p.join(project.path, path));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  setUp(() {
    project = Directory.systemTemp.createTempSync('dartvel_assets_');
    write('assets/images/logo-small.png', 'x');
    write('assets/images/hero@2x.jpg', 'x');
    write('assets/video/marketing.mp4', 'x');
    write('assets/data/pricing.json', 'x');
    write('branding/logo-small.svg', 'x');
    write('pubspec.yaml', '''
name: probe
flutter:
  assets:
    - assets/images/
    - assets/video/marketing.mp4
    - assets/data/pricing.json
    - branding/logo-small.svg
''');
  });

  tearDown(() => project.deleteSync(recursive: true));

  String generate() {
    dvGenerateAssets(root: project.path);
    return File(p.join(project.path, 'lib', 'dartvel_client', 'assets.g.dart'))
        .readAsStringSync();
  }

  test('names each asset after its file', () {
    final String source = generate();

    expect(source, contains("imagesLogoSmall('assets/images/logo-small.png'"));
    expect(source, contains("hero2x('assets/images/hero@2x.jpg'"));
    expect(source, contains("marketingVideo('assets/video/marketing.mp4'"));
    expect(source, contains("pricing('assets/data/pricing.json'"));
  });

  test('a name two files would share takes its folder', () {
    final String source = generate();

    // assets/images/logo-small.png and branding/logo-small.svg.
    expect(source, contains('imagesLogoSmall'));
    expect(source, contains('brandingLogoSmall'));
    expect(source, isNot(contains("  logoSmall(")));
  });

  test('the kind comes from the extension', () {
    final String source = generate();

    expect(source, contains('DVAssetKind.image'));
    expect(source, contains('DVAssetKind.video'));
    expect(source, contains('DVAssetKind.data'));
  });

  test('a project that bundles nothing gets an empty enum, not a broken file',
      () {
    write('pubspec.yaml', 'name: probe\n');

    final String source = generate();

    expect(source, contains('enum DVAsset'));
    expect(source, contains('none('));
  });

  test('a folder listed in pubspec brings the files in it', () {
    final String source = generate();

    expect(source, contains('assets/images/hero@2x.jpg'));
  });
}
