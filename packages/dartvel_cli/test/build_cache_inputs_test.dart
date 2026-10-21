import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/build_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  void write(String name, String data) {
    File(p.join(root.path, name))
      ..createSync(recursive: true)
      ..writeAsStringSync(data);
  }

  String key() => dvWebBuildKey(
    projectRoot: root.path,
    flutterArguments: ['build', 'web'],
    platform: 'web',
    profile: 'release',
    dartvelVersion: 'test',
    flutterVersion: 'test',
  );
  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_cache_inputs');
    addTearDown(() => root.deleteSync(recursive: true));
  });
  test('changing a declared font invalidates the web build', () {
    write(
      'pubspec.yaml',
      'name: app\nflutter:\n  fonts:\n    - family: App\n      fonts:\n        - asset: fonts/app.ttf\n',
    );
    write('fonts/app.ttf', 'old');
    final before = key();
    write('fonts/app.ttf', 'new');
    expect(key(), isNot(before));
  });
  test('changing a path dependency asset invalidates the web build', () {
    write(
      'dependency/pubspec.yaml',
      'name: dependency\nflutter:\n  assets: [assets/]\n',
    );
    write('dependency/assets/data.json', 'old');
    write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'packages': [
          {'name': 'dependency', 'rootUri': '../dependency/'},
        ],
      }),
    );
    final before = key();
    write('dependency/assets/data.json', 'new');
    expect(key(), isNot(before));
  });
  test('an empty output is a valid cache entry', () {
    final source = Directory(p.join(root.path, 'source'))..createSync();
    final cache = DVBuildCache(root.path);
    cache.store('web', 'empty', source);
    expect(
      cache.restore('web', 'empty', Directory(p.join(root.path, 'out'))),
      isTrue,
    );
  });
  test('a manifest cannot restore paths outside the destination', () {
    write('source/content', 'safe');
    final cache = DVBuildCache(root.path);
    cache.store('web', 'entry', Directory(p.join(root.path, 'source')));
    final manifest = File(
      p.join(root.path, '.dartvel/cache/web/entry/manifest.json'),
    );
    final decoded = jsonDecode(manifest.readAsStringSync()) as Map;
    final files = decoded['files'] as Map;
    final details = files.remove('content');
    files['../escaped'] = details;
    write('.dartvel/cache/web/entry/escaped', 'safe');
    manifest.writeAsStringSync(jsonEncode(decoded));
    expect(
      cache.restore('web', 'entry', Directory(p.join(root.path, 'out'))),
      isFalse,
    );
    expect(File(p.join(root.path, 'escaped')).existsSync(), isFalse);
  });
}
