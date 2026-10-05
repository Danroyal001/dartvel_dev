// The pack a web-server binary carries its site in, as the build writes it.
//
// Every web file under web/, the dashboard under admin/ and protected, each
// kept the smallest way the build can find: brotli from the native library
// it is about to embed, gzip where that library has no codec, nothing for a
// format that is compressed already. Encoding at brotli's highest level is
// slow, so the build keeps each encoding and a rebuild reuses it.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/admin_mount.dart';
import 'package:dartvel_cli/src/build/server_assets.dart';
import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:dartvel_core/binary_payload.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final Uri cli = Isolate.resolvePackageUriSync(
      Uri.parse('package:dartvel_cli/src/build/server_assets.dart'))!;
  final String packages =
      p.dirname(p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
  final host = dvHostServerLibrary();
  final File library =
      File(p.join(packages, 'dartvel_shelf', 'lib', 'native', host.subdir, host.name));

  late Directory project;
  late String web;
  final Uint8List js = Uint8List.fromList(utf8.encode(
      List<String>.generate(3000, (int i) => 'function f$i(){return $i}').join('\n')));
  final Random random = Random(9);
  final Uint8List png = Uint8List.fromList(
      <int>[0x89, 0x50, 0x4e, 0x47, ...List<int>.generate(20000, (_) => random.nextInt(256))]);

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_server_assets_');
    web = p.join(project.path, 'build', 'web');
    void write(String path, List<int> bytes) => File(p.join(web, path))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    write('index.html', utf8.encode('<html><title>Site</title></html>' * 10));
    write('main.dart.js', js);
    write('icons/logo.png', png);
    write('main.dart.js.symbols', utf8.encode('symbols'));
    write('.last_build_id', utf8.encode('x'));
    write('__admin/index.html', utf8.encode('<html>Studio</html>' * 10));
    write('__admin/main.dart.js', js);
  });
  tearDown(() => project.deleteSync(recursive: true));

  Future<(DVAssetPack, DVServerAssetsResult)> build({
    DVAssetCompression compression = DVAssetCompression.brotli,
    String? codecLibrary,
    DVAdminMount? admin = const DVAdminMount(path: '/__studio', enabled: true, requiresAuth: true),
  }) async {
    final DVServerAssetsResult result = await dvServerAssetPack(
      projectRoot: project.path,
      webRoot: web,
      admin: admin,
      adminRoot: p.join(web, '__admin'),
      compression: compression,
      codecLibrary: codecLibrary ?? library.path,
    );
    final File file = File(p.join(project.path, 'pack'))..writeAsBytesSync(result.pack);
    return (DVAssetPack.open(file.path, offset: 0, length: result.pack.length)!, result);
  }

  test('carries the site under web/ and the dashboard under admin/, protected', () async {
    final (DVAssetPack pack, _) = await build();
    expect(pack.paths.toSet(), <String>{
      'web/index.html', 'web/main.dart.js', 'web/icons/logo.png',
      'admin/index.html', 'admin/main.dart.js',
    });
    expect(pack['web/main.dart.js']!.protected, isFalse);
    expect(pack['admin/main.dart.js']!.protected, isTrue);
    expect(pack['admin/index.html']!.protected, isTrue);
  });

  test('carries no dashboard for a build without one', () async {
    for (final DVAdminMount? admin in <DVAdminMount?>[
      null,
      const DVAdminMount(path: '/__studio', enabled: false, requiresAuth: true),
    ]) {
      final (DVAssetPack pack, _) = await build(admin: admin);
      expect(pack.paths.where((String path) => path.startsWith('admin/')), isEmpty);
    }
  });

  test('keeps text in brotli and a PNG as it is, and every file reads back whole', () async {
    final (DVAssetPack pack, _) = await build();
    expect(pack['web/main.dart.js']!.encoding, DVAssetEncoding.br);
    expect(pack['web/main.dart.js']!.storedLength, lessThan(js.length ~/ 5));
    expect(pack['web/icons/logo.png']!.encoding, DVAssetEncoding.identity);
    expect(pack.readStored(pack['web/icons/logo.png']!), png);
    for (final String path in pack.paths) {
      final String relative = path.startsWith('admin/')
          ? p.join('__admin', path.substring(6))
          : path.substring(4);
      final Uint8List stored = pack.readStored(pack[path]!);
      if (pack[path]!.encoding == DVAssetEncoding.identity) {
        expect(stored, File(p.join(web, relative)).readAsBytesSync(), reason: path);
      }
    }
  });

  test('stores a file the site and the dashboard share once', () async {
    final (DVAssetPack pack, DVServerAssetsResult result) = await build();
    expect(result.distinctBytes, lessThan(result.storedBytes));
    expect(pack['web/main.dart.js']!.hash, pack['admin/main.dart.js']!.hash);
  });

  test('reuses what an earlier build encoded', () async {
    final (_, DVServerAssetsResult first) = await build();
    expect(first.encoded, greaterThan(0));
    final (DVAssetPack again, DVServerAssetsResult second) = await build();
    expect(second.encoded, 0);
    expect(second.reused, first.encoded);
    expect(again['web/main.dart.js']!.encoding, DVAssetEncoding.br);
  });

  test('keeps gzip when the library has no codec, and nothing when asked for none', () async {
    final (DVAssetPack gzipped, DVServerAssetsResult said) =
        await build(codecLibrary: p.join(project.path, 'no-such-library.so'));
    expect(gzipped['web/main.dart.js']!.encoding, DVAssetEncoding.gzip);
    expect(said.lines.join('\n'), contains('gzip'));
    final (DVAssetPack plain, _) = await build(compression: DVAssetCompression.none);
    expect(plain['web/main.dart.js']!.encoding, DVAssetEncoding.identity);
  });

  test('zstd when that is what was declared', () async {
    final (DVAssetPack pack, _) = await build(compression: DVAssetCompression.zstd);
    expect(pack['web/main.dart.js']!.encoding, DVAssetEncoding.zstd);
  });

  test('the declared compression is read by name, and anything else is brotli', () {
    expect(dvAssetCompression('zstd'), DVAssetCompression.zstd);
    expect(dvAssetCompression('gzip'), DVAssetCompression.gzip);
    expect(dvAssetCompression('none'), DVAssetCompression.none);
    expect(dvAssetCompression(false), DVAssetCompression.none);
    expect(dvAssetCompression(null), DVAssetCompression.brotli);
    expect(dvAssetCompression('brotli'), DVAssetCompression.brotli);
    expect(dvAssetCompression('lzma'), DVAssetCompression.brotli);
  });
}
