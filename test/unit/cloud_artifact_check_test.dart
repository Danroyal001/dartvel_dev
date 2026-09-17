// tool/ci/cloud_artifact_check.dart is what stands between a cloud build that
// uploaded the right thing and one that uploaded a directory with the right
// name. Each target is given what its build makes, which must pass, and the
// nearest wrong thing, which must not: an empty file, the GUI build under a
// terminal name, an iPhone app under a tvOS one, a Chromium manifest in a
// Firefox bundle.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const List<int> _elf = <int>[0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0];
const List<int> _machO = <int>[0xcf, 0xfa, 0xed, 0xfe, 7, 0, 0, 1];

late Directory _root;

String _dir(String name) => Directory(p.join(_root.path, name)).path;

void _file(String dir, String path, Object content) {
  final File file = File(p.join(dir, path))..parent.createSync(recursive: true);
  if (content is String) {
    file.writeAsStringSync(content);
  } else {
    file.writeAsBytesSync(content as List<int>);
  }
}

/// A stored (uncompressed) zip holding [entries], enough for a central
/// directory reader.
List<int> _zip(Map<String, List<int>> entries) {
  final BytesBuilder out = BytesBuilder();
  final BytesBuilder central = BytesBuilder();
  List<int> u16(int v) => <int>[v & 0xff, (v >> 8) & 0xff];
  List<int> u32(int v) => <int>[...u16(v & 0xffff), ...u16((v >> 16) & 0xffff)];
  for (final MapEntry<String, List<int>> e in entries.entries) {
    final List<int> name = utf8.encode(e.key);
    final int offset = out.length;
    out
      ..add(u32(0x04034b50))
      ..add(u16(20))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u32(0))
      ..add(u32(e.value.length))
      ..add(u32(e.value.length))
      ..add(u16(name.length))
      ..add(u16(0))
      ..add(name)
      ..add(e.value);
    central
      ..add(u32(0x02014b50))
      ..add(u16(20))
      ..add(u16(20))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u32(0))
      ..add(u32(e.value.length))
      ..add(u32(e.value.length))
      ..add(u16(name.length))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u16(0))
      ..add(u32(0))
      ..add(u32(offset))
      ..add(name);
  }
  final int start = out.length;
  final List<int> dir = central.takeBytes();
  out
    ..add(dir)
    ..add(u32(0x06054b50))
    ..add(u16(0))
    ..add(u16(0))
    ..add(u16(entries.length))
    ..add(u16(entries.length))
    ..add(u32(dir.length))
    ..add(u32(start))
    ..add(u16(0));
  return out.takeBytes();
}

Future<ProcessResult> _check(String target, String dir) => Process.run(
      Platform.resolvedExecutable,
      <String>['tool/ci/cloud_artifact_check.dart', target, dir],
    );

Future<void> _passes(String target, String dir) async {
  final ProcessResult r = await _check(target, dir);
  expect(r.exitCode, 0, reason: '$target should pass: ${r.stdout}${r.stderr}');
}

Future<void> _fails(String target, String dir, String why) async {
  final ProcessResult r = await _check(target, dir);
  expect(r.exitCode, isNot(0), reason: '$target should fail: $why');
  expect('${r.stderr}', contains(why));
}

void main() {
  setUp(() => _root = Directory.systemTemp.createTempSync('cloud_artifact_check_'));
  tearDown(() => _root.deleteSync(recursive: true));

  test('fireos is an APK like android', () async {
    final String good = _dir('good');
    _file(good, 'app-debug.apk',
        _zip(<String, List<int>>{'AndroidManifest.xml': <int>[1], 'classes.dex': <int>[1], 'lib/arm64-v8a/libapp.so': <int>[1]}));
    await _passes('fireos', good);
    final String bad = _dir('bad');
    _file(bad, 'app-debug.apk', 'not a zip');
    await _fails('fireos', bad, 'is not a zip');
  });

  test('a Chrome extension is an MV3 service worker bundle, and a Firefox one is not', () async {
    final String chrome = _dir('chrome');
    _file(chrome, 'manifest.json',
        jsonEncode(<String, Object?>{'manifest_version': 3, 'background': <String, Object?>{'service_worker': 'background.js'}}));
    _file(chrome, 'background.js', '//');
    _file(chrome, 'index.html', '<html>');
    _file(chrome, 'main.dart.js', 'x' * 2000);
    await _passes('chrome-extension', chrome);
    await _fails('firefox-extension', chrome, 'background.scripts');

    final String firefox = _dir('firefox');
    _file(firefox, 'manifest.json',
        jsonEncode(<String, Object?>{'manifest_version': 3, 'background': <String, Object?>{'scripts': <String>['background.js']}}));
    _file(firefox, 'background.js', '//');
    _file(firefox, 'index.html', '<html>');
    _file(firefox, 'main.dart.js', 'x' * 2000);
    await _passes('firefox-extension', firefox);
    await _fails('chrome-extension', firefox, 'service_worker');

    File(p.join(firefox, 'main.dart.js')).deleteSync();
    await _fails('firefox-extension', firefox, 'main.dart.js');
  });

  test('a VS Code extension has its host script, its manifest and the Flutter web build', () async {
    final String good = _dir('vscode');
    _file(good, 'package.json', jsonEncode(<String, Object?>{'main': './out/src/extension.js', 'engines': <String, String>{'vscode': '^1.80.0'}}));
    _file(good, 'out/src/extension.js', 'exports.activate = () => {};');
    _file(good, 'build/web/flutter_bootstrap.js', '//');
    _file(good, 'build/web/main.dart.js', 'x' * 2000);
    await _passes('vscode', good);
    File(p.join(good, 'out/src/extension.js')).deleteSync();
    await _fails('vscode', good, 'extension.js');
  });

  test('a tvOS build is a simulator app for Apple TV, not an iPhone app', () async {
    final String tv = _dir('tv');
    _file(tv, 'Runner.app/Info.plist', 'bplist00...DTPlatformName...appletvsimulator...');
    _file(tv, 'Runner.app/Runner', _machO);
    await _passes('tvos', tv);

    final String phone = _dir('phone');
    _file(phone, 'Runner.app/Info.plist', 'bplist00...DTPlatformName...iphoneos...');
    _file(phone, 'Runner.app/Runner', _machO);
    await _fails('tvos', phone, 'appletv');

    final String empty = _dir('empty');
    _file(empty, 'Runner.app/Info.plist', 'appletvsimulator');
    _file(empty, 'Runner.app/Runner', '');
    await _fails('tvos', empty, 'not a Mach-O');
  });

  test('a terminal build is the flt embedder and its engine, with no GTK runner', () async {
    final String good = _dir('terminal');
    _file(good, 'flt', _elf);
    _file(good, 'run.sh', '#!/bin/sh\nexec "\$here/flt"\n');
    _file(good, 'lib/libflutter_engine.so', _elf);
    _file(good, 'data/icudtl.dat', <int>[1]);
    _file(good, 'data/flutter_assets/kernel_blob.bin', <int>[1]);
    await _passes('linux-cli', good);

    final String gui = _dir('gui');
    _file(gui, 'basic_app', _elf);
    _file(gui, 'lib/libflutter_linux_gtk.so', _elf);
    _file(gui, 'data/icudtl.dat', <int>[1]);
    await _fails('linux-cli', gui, 'GTK');

    File(p.join(gui, 'lib/libflutter_linux_gtk.so')).deleteSync();
    await _fails('linux-cli', gui, 'flt');

    _file(good, 'lib/libflutter_linux_gtk.so', _elf);
    await _fails('linux-cli', good, 'GTK');
  });

  test('an eLinux bundle is Sony\'s client, the engine and AOT code, with no GTK runner', () async {
    final String good = _dir('elinux');
    _file(good, 'flutter-client', _elf);
    _file(good, 'lib/libflutter_engine.so', _elf);
    _file(good, 'lib/libapp.so', _elf);
    _file(good, 'data/icudtl.dat', <int>[1]);
    _file(good, 'data/flutter_assets/AssetManifest.bin', <int>[1]);
    await _passes('sony-elinux', good);

    File(p.join(good, 'lib/libapp.so')).writeAsStringSync('');
    await _fails('sony-elinux', good, 'not an ELF');
  });

  test('a TPK is a signed Tizen package carrying the engine and the app', () async {
    final String good = _dir('tizen');
    _file(good, 'basic_app-1.0.0.tpk', _zip(<String, List<int>>{
      'tizen-manifest.xml': utf8.encode('<manifest/>'),
      'author-signature.xml': <int>[1],
      'lib/libflutter_engine.so': <int>[1],
      'lib/libapp.so': <int>[1],
      'res/flutter_assets/AssetManifest.bin': <int>[1],
    }));
    await _passes('tizen', good);

    final String unsigned = _dir('unsigned');
    _file(unsigned, 'basic_app-1.0.0.tpk', _zip(<String, List<int>>{
      'tizen-manifest.xml': utf8.encode('<manifest/>'),
      'bin/runner': <int>[1],
    }));
    await _fails('tizen', unsigned, 'author-signature.xml');

    final String runnerOnly = _dir('runner-only');
    _file(runnerOnly, 'basic_app-1.0.0.tpk', _zip(<String, List<int>>{
      'tizen-manifest.xml': utf8.encode('<manifest/>'),
      'author-signature.xml': <int>[1],
      'bin/runner': <int>[1],
    }));
    await _fails('tizen', runnerOnly, 'libflutter_engine.so');
  });
}
