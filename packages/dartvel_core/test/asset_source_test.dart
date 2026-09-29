// Where the server reads a site's files from: a directory during development
// and preview, the pack inside the executable in a web-server binary.
//
// Everything that reads the site -- the static files, the shell and manifest
// a page is rendered from, an image's source, Studio's files -- asks the
// source registered for its root, so a binary serves from its pack with no
// file written, and every root keeps the `String` it always was.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/src/process/asset_pack.dart';
import 'package:dartvel_core/src/web/asset_source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('dv_asset_source_'));
  tearDown(() {
    DVAssetSources.clear();
    work.deleteSync(recursive: true);
  });

  Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

  DVAssetPack pack(List<DVAssetPackEntry> entries) {
    final Uint8List bytes = dvWriteAssetPack(entries);
    final File file = File(p.join(work.path, 'server'))..writeAsBytesSync(bytes);
    return DVAssetPack.open(file.path, offset: 0, length: bytes.length)!;
  }

  group('a directory', () {
    test('serves its files, and a missing file or a directory is null', () {
      File(p.join(work.path, 'site', 'assets', 'a.js'))
        ..createSync(recursive: true)
        ..writeAsStringSync('a()');
      final DVAssetSource source = DVAssetSources.at(p.join(work.path, 'site'));
      final DVAssetFile file = source.file('assets/a.js')!;
      expect(file.bytes(), text('a()'));
      expect(file.size, 3);
      expect(file.storedEncoding, DVAssetEncoding.identity);
      expect(file.protected, isFalse);
      expect(source.file('assets'), isNull);
      expect(source.file('assets/b.js'), isNull);
      expect(source.file('../site/assets/a.js'), isNull);
      expect(source.embedded, isFalse);
    });

    test('names the content, and a changed file gets a new name', () {
      final File a = File(p.join(work.path, 'a.txt'))..writeAsStringSync('one');
      final DVAssetSource source = DVAssetSources.at(work.path);
      final String first = source.file('a.txt')!.hash;
      a.writeAsStringSync('two, longer');
      expect(source.file('a.txt')!.hash, isNot(first));
    });
  });

  group('a pack', () {
    test('serves the files under its prefix and nothing else', () {
      final DVAssetPack assets = pack(<DVAssetPackEntry>[
        DVAssetPackEntry('web/index.html', text('<html>')),
        DVAssetPackEntry('admin/index.html', text('<studio>'), protected: true),
      ]);
      DVAssetSources.register('/srv/app/server/web', DVPackedAssets(assets, prefix: 'web/'));
      DVAssetSources.register('/srv/app/server/admin', DVPackedAssets(assets, prefix: 'admin/'));
      final DVAssetSource web = DVAssetSources.at('/srv/app/server/web');
      final DVAssetSource admin = DVAssetSources.at('/srv/app/server/admin');
      expect(web.file('index.html')!.bytes(), text('<html>'));
      expect(web.file('index.html')!.protected, isFalse);
      expect(admin.file('index.html')!.bytes(), text('<studio>'));
      expect(admin.file('index.html')!.protected, isTrue);
      // One root never reaches another's files through its path.
      expect(web.file('../admin/index.html'), isNull);
      expect(web.file('admin/index.html'), isNull);
      expect(web.embedded, isTrue);
      expect(web.buildId, assets.buildId);
    });

    test('keeps a file as it is stored, and decodes it on request', () {
      final Uint8List js = text('main();\n' * 500);
      final DVAssetPack assets = pack(<DVAssetPackEntry>[
        DVAssetPackEntry('web/main.dart.js', js,
            stored: Uint8List.fromList(gzip.encode(js)), encoding: DVAssetEncoding.gzip),
      ]);
      final DVAssetFile file = DVPackedAssets(assets, prefix: 'web/').file('main.dart.js')!;
      expect(file.storedEncoding, DVAssetEncoding.gzip);
      expect(gzip.decode(file.stored()), js);
      expect(file.bytes(), js);
      expect(file.size, js.length);
    });
  });

  test('a root nothing was registered for is the directory of that name', () {
    expect(DVAssetSources.at(work.path).embedded, isFalse);
    DVAssetSources.register(work.path, DVPackedAssets(pack(const <DVAssetPackEntry>[]), prefix: 'web/'));
    expect(DVAssetSources.at(work.path).embedded, isTrue);
  });

  group('a request path', () {
    test('becomes the file it names', () {
      expect(dvAssetPath('/assets/app.js'), 'assets/app.js');
      expect(dvAssetPath('assets/app.js'), 'assets/app.js');
      expect(dvAssetPath('/assets/my%20font.ttf'), 'assets/my font.ttf');
      expect(dvAssetPath('/a//b/./c.js'), 'a/b/c.js');
    });

    test('that leaves the site, or is no file, is refused', () {
      for (final String bad in <String>[
        '/', '', '/../secret', '/a/../../b', '/%2e%2e/x', '/a\\b', '/%5c', '/c:/x', '/%zz',
      ]) {
        expect(dvAssetPath(bad), isNull, reason: bad);
      }
    });
  });
}
