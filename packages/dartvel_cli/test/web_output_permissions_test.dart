// A web build a shared host cannot read.
//
// The disk a build runs on decides the modes its files are created with, and
// one here made every directory 756: no execute for others. Zipped and
// extracted on a LiteSpeed host, whose static server reads as another user,
// every file below the root was unreachable -- icons, assets, canvaskit --
// and the rewrite answered index.html for each, so the manifest icon was "not
// a valid image" and the app failed parsing HTML as its asset manifest. Files
// at the root loaded, which is why the page started at all.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:dartvel_cli/src/build/server_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

int modeOf(String path) => FileStat.statSync(path).mode & 0x1FF;

void main() {
  late Directory web;

  setUp(() {
    web = Directory.systemTemp.createTempSync('dv_web_modes_');
    Directory(p.join(web.path, 'icons', 'nested')).createSync(recursive: true);
    File(p.join(web.path, 'index.html')).writeAsStringSync('<html>');
    File(p.join(web.path, 'icons', 'Icon-192.png')).writeAsBytesSync([1]);
    File(p.join(web.path, 'icons', 'nested', 'a.json')).writeAsStringSync('{}');
    Process.runSync('chmod', ['-R', 'u=rwX,g=rX,o=rw', web.path]);
    Process.runSync('chmod', ['700', web.path]);
  });

  tearDown(() => web.deleteSync(recursive: true));

  test('every directory can be entered and every file read by another user',
      () {
    expect(modeOf(p.join(web.path, 'icons')), isNot(0x1ED),
        reason: 'the fixture starts unreadable');

    dvMakeWebOutputServable(web);

    for (final String dir in ['', 'icons', p.join('icons', 'nested')]) {
      expect(modeOf(p.join(web.path, dir)), 0x1ED, // 755
          reason: '$dir must be 755');
    }
    for (final String file in [
      'index.html',
      p.join('icons', 'Icon-192.png'),
      p.join('icons', 'nested', 'a.json'),
    ]) {
      expect(modeOf(p.join(web.path, file)), 0x1A4, // 644
          reason: '$file must be 644');
    }
  });

  test('nothing is left writable by group or others', () {
    dvMakeWebOutputServable(web);
    final List<FileSystemEntity> all = web.listSync(recursive: true);
    for (final FileSystemEntity e in all) {
      expect(modeOf(e.path) & 0x12, 0, reason: '${e.path} is writable by others');
    }
  });
}
