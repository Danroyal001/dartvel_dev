// The generated application hands its splash to the runtime, so a device
// shows the same splash as the launch screen -- with the loading bar -- while
// the boot steps run. The picture is carried in the generated code, resized
// to what the launch screen draws, because a device build has no web server
// to fetch dartvel-splash.png from.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _applicationFor(Directory root, Map<String, Object?> dartvel) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'splash_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Splash App',
    seoTitle: 'Splash App',
    seoDesc: 'Splash App',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(dartvel),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'application.g.dart'))
      .readAsStringSync();
}

Directory _project() {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_boot_splash_');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage() Widget _index() => DVText("Home");
''');
  return root;
}

void main() {
  test('DV.run hands the project\'s splash, with its loading bar, to the runtime', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    final String out = await _applicationFor(root, <String, Object?>{
      'splash': <String, Object?>{
        'color': '#112233',
        'darkColor': '#000000',
        'progressColor': '#FF0000',
      },
    });
    expect(out, contains('splash: _dvBootSplash'));
    final RegExpMatch? splash =
        RegExp(r'final runtime\.DVStudioSplash\? _dvBootSplash = (.*?);\n').firstMatch(out);
    expect(splash, isNotNull, reason: out);
    expect(splash!.group(1), contains('color: Color(0xFF112233)'));
    expect(splash.group(1), contains('darkColor: Color(0xFF000000)'));
    expect(splash.group(1), contains('progressColor: Color(0xFFFF0000)'));
    expect(splash.group(1), isNot(contains('imageBytes')));
  });

  test('the picture is carried in the code at the size the launch screen draws it', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    final DVRgbaImage big = DVRgbaImage(600, 300);
    for (int i = 0; i < big.pixels.length; i++) {
      big.pixels[i] = 255;
    }
    File(p.join(root.path, 'splash.png')).writeAsBytesSync(dvPngEncode(big));
    final String out = await _applicationFor(root, <String, Object?>{
      'splash': <String, Object?>{'image': 'splash.png', 'imageWidth': 100},
    });
    final RegExpMatch? bytes =
        RegExp(r"imageBytes: base64Decode\('([A-Za-z0-9+/=]+)'\)").firstMatch(out);
    expect(bytes, isNotNull, reason: out);
    final DVRgbaImage carried = dvPngDecode(base64Decode(bytes!.group(1)!));
    // Three device pixels per logical pixel, the densest common screen.
    expect(carried.width, 300);
    expect(carried.height, 150);
    expect(out, contains('imageWidth: 100'));
  });

  test('no loading bar asked for: no splash is handed over, and the launch '
      'screen stays until the first frame as before', () async {
    final Directory root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    final String out = await _applicationFor(root, <String, Object?>{
      'splash': <String, Object?>{'progress': false},
    });
    expect(out, contains('final runtime.DVStudioSplash? _dvBootSplash = null;'));
  });
}
