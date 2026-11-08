// Package Structure: target-specific and runtime-specific implementation
// lives under native/, in a directory named for the target, and there is no
// top-level wasm/ or nodejs/ integration tree beside it. "Unsupported
// platform targets fail during validation ... rather than silently ignoring
// work": a native/andriod/ that nothing reads is work silently ignored.
import 'dart:io';

import 'package:dartvel_cli/src/build/declaration_check.dart';
import 'package:dartvel_cli/src/build/native_tree_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory project({List<String> directories = const <String>[]}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_native_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml'))
      .writeAsStringSync('name: shopfront\ndartvel:\n  pagesDir: lib/pages\n');
  for (final String directory in directories) {
    Directory(p.join(root.path, directory)).createSync(recursive: true);
    File(p.join(root.path, directory, 'impl.txt')).writeAsStringSync('x');
  }
  return root;
}

void main() {
  test('a project with no native code has nothing to refuse', () {
    final DVNativeTreeCheck check = DVNativeTreeCheck.run(project().path);

    expect(check.ok, isTrue);
    expect(check.lines, isEmpty);
  });

  test('every directory the spec names under native/ is accepted', () {
    final DVNativeTreeCheck check = DVNativeTreeCheck.run(
      project(
        directories: <String>[
          for (final String name in <String>[
            'android',
            'ios',
            'macos',
            'windows',
            'linux',
            'fireos',
            'tvos',
            'tizen',
            'webos',
            'sony-elinux',
            'fuchsia',
            'web',
            'wasm',
            'nodejs',
          ])
            'native/$name',
        ],
      ).path,
    );

    expect(check.ok, isTrue, reason: check.lines.join('\n'));
  });

  test('a top-level wasm/ tree is refused and pointed at native/wasm', () {
    final DVNativeTreeCheck check = DVNativeTreeCheck.run(
      project(directories: <String>['wasm']).path,
    );

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('wasm/'));
    expect(check.lines.join('\n'), contains('native/wasm/'));
  });

  test('a top-level nodejs/ tree is refused and pointed at native/nodejs', () {
    final DVNativeTreeCheck check = DVNativeTreeCheck.run(
      project(directories: <String>['nodejs']).path,
    );

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('native/nodejs/'));
  });

  test('a native/ directory named for no target is refused, not ignored', () {
    final DVNativeTreeCheck check = DVNativeTreeCheck.run(
      project(directories: <String>['native/andriod', 'native/ios']).path,
    );

    expect(check.ok, isFalse);
    final String said = check.lines.join('\n');
    expect(said, contains('native/andriod/'));
    // Says what it could have been called, so the typo is a one-line fix.
    expect(said, contains('android'));
    // The correctly named sibling is not reported.
    expect(said, isNot(contains('native/ios/')));
  });

  test('empty native/ target directories are not refused', () {
    final Directory root = project();
    Directory(p.join(root.path, 'native', 'andriod'))
        .createSync(recursive: true);
    Directory(p.join(root.path, 'wasm')).createSync();

    // Nothing in them is work being ignored.
    expect(DVNativeTreeCheck.run(root.path).ok, isTrue);
  });

  test("Flutter's web/ scaffold is not taken for an integration tree", () {
    // dartvel build web generates web/ with `flutter create`; Flutter will
    // not read it from anywhere else. It is ephemeral build input, not a
    // second home for browser integrations.
    final DVNativeTreeCheck check = DVNativeTreeCheck.run(
      project(directories: <String>['web']).path,
    );

    expect(check.ok, isTrue);
  });

  test('dartvel build refuses the layout before generating anything', () {
    final DVDeclarationCheck check = DVDeclarationCheck.run(
      project(directories: <String>['wasm']).path,
    );

    expect(check.ok, isFalse);
    expect(check.lines.join('\n'), contains('native/wasm/'));
  });
}
