import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/build_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The build cache never serves a stale result: every input that can change
/// the output changes the key, and an entry that is not exactly what was
/// stored is never read.
void main() {
  late Directory project;

  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String key({List<String> arguments = const <String>['build', 'web', '--release'], String profile = 'release', String flutter = 'f1', String dartvel = '0.10.0'}) =>
      dvWebBuildKey(
        projectRoot: project.path,
        flutterArguments: arguments,
        platform: 'web',
        profile: profile,
        dartvelVersion: dartvel,
        flutterVersion: flutter,
      );

  setUp(() {
    project = Directory.systemTemp.createTempSync('dartvel_build_cache_');
    addTearDown(() => project.deleteSync(recursive: true));
    write('pubspec.yaml', '''
name: cached_app
flutter:
  assets:
    - assets/images/
    - path: assets/data.json
  uses-material-design: true
''');
    write('pubspec.lock', 'packages: {}\n');
    write('lib/main.dart', 'void main() {}\n');
    write('web/index.html', '<html></html>');
    write('assets/images/logo.png', 'png-bytes');
    write('assets/data.json', '{"a":1}');
    write('assets/unlisted.txt', 'not an asset');
  });

  group('the key', () {
    test('is the same for the same inputs', () {
      expect(key(), key());
    });

    for (final (String what, String file, String content) in <(String, String, String)>[
      ('a lib file', 'lib/main.dart', 'void main() { print(1); }\n'),
      ('a new lib file', 'lib/extra.dart', 'int x = 1;\n'),
      ('a declared asset directory', 'assets/images/logo.png', 'other-png'),
      ('a declared asset file', 'assets/data.json', '{"a":2}'),
      ('the lockfile', 'pubspec.lock', 'packages: {x: 1}\n'),
      ('the pubspec', 'pubspec.yaml', 'name: cached_app\n'),
      ('web/', 'web/index.html', '<html><body></body></html>'),
    ]) {
      test('changes when $what changes by a byte', () {
        final String before = key();
        write(file, content);
        expect(key(), isNot(before));
      });
    }

    test('changes when a file is deleted', () {
      final String before = key();
      File(p.join(project.path, 'lib', 'main.dart')).deleteSync();
      expect(key(), isNot(before));
    });

    test('does not change for a file nothing reads', () {
      final String before = key();
      write('assets/unlisted.txt', 'still not an asset');
      write('README.md', '# notes');
      expect(key(), before);
    });

    test('changes with the flags, the profile, Flutter and Dartvel', () {
      final String before = key();
      expect(key(arguments: const <String>['build', 'web', '--profile']), isNot(before));
      expect(key(profile: 'profile'), isNot(before));
      expect(key(flutter: 'f2'), isNot(before));
      expect(key(dartvel: '0.10.1'), isNot(before));
    });

    test('covers the source of a package depended on by path', () {
      final Directory sibling = Directory(p.join(project.parent.path, '${p.basename(project.path)}_sibling'));
      addTearDown(() => sibling.deleteSync(recursive: true));
      File(p.join(sibling.path, 'lib', 'sibling.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('int y = 1;');
      File(p.join(sibling.path, 'pubspec.yaml')).writeAsStringSync('name: sibling\n');
      write('.dart_tool/package_config.json', jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{'name': 'sibling', 'rootUri': '../../${p.basename(sibling.path)}', 'packageUri': 'lib/'},
          <String, Object?>{'name': 'hosted', 'rootUri': 'file:///home/u/.pub-cache/hosted/pub.dev/hosted-1.0.0', 'packageUri': 'lib/'},
        ],
      }));
      expect(dvPathDependencies(project.path).map((d) => d.name), <String>['sibling']);
      final String before = key();
      File(p.join(sibling.path, 'lib', 'sibling.dart')).writeAsStringSync('int y = 2;');
      expect(key(), isNot(before));
    });

    test('reads both forms of declared asset', () {
      expect(dvDeclaredAssetPaths(project.path), <String>['assets/images/', 'assets/data.json']);
    });
  });

  group('the cache', () {
    late Directory output;

    setUp(() {
      output = Directory(p.join(project.path, 'build', 'web'));
      File(p.join(output.path, 'main.dart.js'))
        ..createSync(recursive: true)
        ..writeAsStringSync('compiled');
      File(p.join(output.path, 'assets', 'a.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[1, 2, 3]);
    });

    test('restores exactly what was stored, replacing what was there', () {
      final DVBuildCache cache = DVBuildCache(project.path);
      cache.store('flutter-web', 'k1', output);
      File(p.join(output.path, 'main.dart.js')).writeAsStringSync('post-processed');
      File(p.join(output.path, 'leftover.txt')).writeAsStringSync('from a later step');
      expect(cache.restore('flutter-web', 'k1', output), isTrue);
      expect(File(p.join(output.path, 'main.dart.js')).readAsStringSync(), 'compiled');
      expect(File(p.join(output.path, 'assets', 'a.png')).readAsBytesSync(), <int>[1, 2, 3]);
      expect(File(p.join(output.path, 'leftover.txt')).existsSync(), isFalse);
    });

    test('a missing entry restores nothing and leaves the output alone', () {
      final DVBuildCache cache = DVBuildCache(project.path);
      expect(cache.restore('flutter-web', 'nope', output), isFalse);
      expect(File(p.join(output.path, 'main.dart.js')).existsSync(), isTrue);
    });

    test('a changed byte in an entry makes it invalid, and it is deleted', () {
      final DVBuildCache cache = DVBuildCache(project.path);
      cache.store('flutter-web', 'k1', output);
      final Directory entry = Directory(p.join(project.path, dvBuildCacheDirectory, 'flutter-web', 'k1'));
      File(p.join(entry.path, 'files', 'main.dart.js')).writeAsStringSync('tampered');
      expect(cache.restore('flutter-web', 'k1', output), isFalse);
      expect(entry.existsSync(), isFalse);
      expect(File(p.join(output.path, 'main.dart.js')).readAsStringSync(), 'compiled');
    });

    test('an entry without its manifest (an interrupted store) is never read', () {
      final DVBuildCache cache = DVBuildCache(project.path);
      cache.store('flutter-web', 'k1', output);
      final Directory entry = Directory(p.join(project.path, dvBuildCacheDirectory, 'flutter-web', 'k1'));
      File(p.join(entry.path, 'manifest.json')).deleteSync();
      expect(cache.has('flutter-web', 'k1'), isFalse);
      expect(entry.existsSync(), isFalse);
    });

    test('a missing file in an entry makes it invalid', () {
      final DVBuildCache cache = DVBuildCache(project.path);
      cache.store('flutter-web', 'k1', output);
      File(p.join(project.path, dvBuildCacheDirectory, 'flutter-web', 'k1', 'files', 'assets', 'a.png')).deleteSync();
      expect(cache.restore('flutter-web', 'k1', output), isFalse);
    });

    test('--no-cache reads nothing and writes nothing', () {
      final DVBuildCache off = DVBuildCache(project.path, enabled: false);
      off.store('flutter-web', 'k1', output);
      expect(Directory(p.join(project.path, dvBuildCacheDirectory)).existsSync(), isFalse);
      DVBuildCache(project.path).store('flutter-web', 'k1', output);
      expect(off.restore('flutter-web', 'k1', output), isFalse);
    });

    test('keeps only the newest entries of a stage', () async {
      final DVBuildCache cache = DVBuildCache(project.path, keepPerStage: 2);
      for (final String key in <String>['a', 'b', 'c']) {
        cache.store('flutter-web', key, output);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(cache.has('flutter-web', 'a'), isFalse);
      expect(cache.has('flutter-web', 'b'), isTrue);
      expect(cache.has('flutter-web', 'c'), isTrue);
    });

    test('keeps the whole cache under its size cap, dropping the oldest', () async {
      final DVBuildCache cache = DVBuildCache(project.path, maxBytes: 20);
      cache.store('flutter-web', 'old', output);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cache.store('semantics', 'new', output);
      expect(cache.has('flutter-web', 'old'), isFalse);
      expect(cache.has('semantics', 'new'), isTrue);
    });
      test('many entries from one build all survive: groups are pruned, not entries', () async {
      final DVBuildCache cache = DVBuildCache(project.path, keepPerStage: 3);
      for (int route = 0; route < 65; route++) {
        cache.store('semantics-build1', 'route$route', output, prune: false);
      }
      cache.pruneGroups('semantics-');
      for (int route = 0; route < 65; route++) {
        expect(cache.has('semantics-build1', 'route$route'), isTrue, reason: 'route$route');
      }
      for (final String build in <String>['build2', 'build3', 'build4']) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        cache.store('semantics-$build', 'route0', output, prune: false);
        cache.pruneGroups('semantics-');
      }
      expect(cache.has('semantics-build1', 'route0'), isFalse, reason: 'the oldest build goes');
      expect(cache.has('semantics-build4', 'route0'), isTrue);
    });
  });
}
