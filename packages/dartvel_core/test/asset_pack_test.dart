// The indexed asset pack a web-server binary carries its web files in.
//
// The binary used to carry the whole web app as one gzip stream and write
// every file of it into its data directory at start, so a 50 MB site cost
// 50 MB of disk and the time to inflate it before the first request. The pack
// is an index and the files' bytes: the index is read at start, a file's
// bytes are read when it is asked for, and nothing is written anywhere.
//
// These drive the format directly: a pack placed at an offset inside a
// larger file, as it sits inside an executable.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_core/src/process/asset_pack.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('dv_asset_pack_'));
  tearDown(() => work.deleteSync(recursive: true));

  /// [pack] written into a file after [before] bytes of something else, as
  /// it sits inside an executable, and opened there.
  DVAssetPack place(Uint8List pack, {int before = 4099}) {
    final File file = File(p.join(work.path, 'host.bin'))
      ..writeAsBytesSync(<int>[...List<int>.filled(before, 7), ...pack, 1, 2, 3]);
    final DVAssetPack? opened =
        DVAssetPack.open(file.path, offset: before, length: pack.length);
    expect(opened, isNotNull, reason: 'the pack did not open');
    return opened!;
  }

  Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

  /// A gzip encoding, standing in for the build's brotli: it is the codec
  /// dart:io has, and the pack treats every encoding alike.
  DVAssetPackEntry gzipped(String path, Uint8List bytes, {bool protected = false}) =>
      DVAssetPackEntry(path, bytes,
          stored: Uint8List.fromList(gzip.encode(bytes)),
          encoding: DVAssetEncoding.gzip,
          protected: protected);

  test('every file reads back as it was written', () {
    final Map<String, Uint8List> files = <String, Uint8List>{
      'index.html': text('<!doctype html><title>x</title>'),
      'assets/app.js': text('main();' * 50),
      'icons/Icon-192.png': Uint8List.fromList(List<int>.generate(3000, (int i) => i * 31 % 256)),
      'empty.txt': Uint8List(0),
    };
    final DVAssetPack pack = place(dvWriteAssetPack(<DVAssetPackEntry>[
      for (final MapEntry<String, Uint8List> f in files.entries) DVAssetPackEntry(f.key, f.value),
    ]));
    expect(pack.paths.toSet(), files.keys.toSet());
    for (final MapEntry<String, Uint8List> f in files.entries) {
      final DVPackedAsset asset = pack[f.key]!;
      expect(asset.size, f.value.length);
      expect(pack.read(asset), f.value, reason: f.key);
    }
  });

  test('an encoded file is kept as encoded and decodes to the original', () {
    final Uint8List js = text('function f(){return 1}\n' * 400);
    final DVAssetPack pack = place(dvWriteAssetPack(<DVAssetPackEntry>[gzipped('main.dart.js', js)]));
    final DVPackedAsset asset = pack['main.dart.js']!;
    expect(asset.encoding, DVAssetEncoding.gzip);
    expect(asset.storedLength, lessThan(js.length ~/ 10));
    expect(asset.size, js.length);
    // Served as it is to a client that accepts it: no work at all.
    expect(gzip.decode(pack.readStored(asset)), js);
    // Decoded once for one that does not.
    expect(pack.read(asset), js);
  });

  test('an encoding that saves nothing is not kept', () {
    final Random random = Random(42);
    final Uint8List noise = Uint8List.fromList(List<int>.generate(2048, (_) => random.nextInt(256)));
    final DVAssetPack pack = place(dvWriteAssetPack(<DVAssetPackEntry>[gzipped('noise.bin', noise)]));
    expect(pack['noise.bin']!.encoding, DVAssetEncoding.identity);
    expect(pack.readStored(pack['noise.bin']!), noise);
  });

  test('formats that are compressed already are not worth encoding', () {
    for (final String path in <String>[
      'a.png', 'b.jpg', 'c.jpeg', 'd.webp', 'e.woff2', 'f.gif', 'g.avif',
      'h.zip', 'i.gz', 'j.br', 'k.zst', 'l.mp4', 'm.webm', 'n.mp3', 'o.ogg', 'p.woff',
    ]) {
      expect(dvAssetWorthEncoding(path), isFalse, reason: path);
    }
    for (final String path in <String>[
      'index.html', 'main.dart.js', 'canvaskit/skwasm.wasm', 'styles.css',
      'manifest.json', 'assets/NOTICES', 'fonts/Manrope.ttf', 'icon.svg', 'x.otf',
    ]) {
      expect(dvAssetWorthEncoding(path), isTrue, reason: path);
    }
  });

  test('identical files are stored once', () {
    final Uint8List wasm = Uint8List.fromList(List<int>.generate(100000, (int i) => (i * 7919) & 0xff));
    final Uint8List one = dvWriteAssetPack(<DVAssetPackEntry>[DVAssetPackEntry('web/canvaskit.wasm', wasm)]);
    final Uint8List two = dvWriteAssetPack(<DVAssetPackEntry>[
      DVAssetPackEntry('web/canvaskit.wasm', wasm),
      DVAssetPackEntry('admin/canvaskit.wasm', wasm, protected: true),
    ]);
    expect(two.length, lessThan(one.length + 1000));
    final DVAssetPack pack = place(two);
    expect(pack.read(pack['admin/canvaskit.wasm']!), wasm);
    expect(pack.read(pack['web/canvaskit.wasm']!), wasm);
  });

  test('a protected file is marked, and a public copy of the same bytes is not', () {
    final Uint8List js = text('studio();' * 100);
    final DVAssetPack pack = place(dvWriteAssetPack(<DVAssetPackEntry>[
      DVAssetPackEntry('admin/main.dart.js', js, protected: true),
      DVAssetPackEntry('web/main.dart.js', js),
    ]));
    expect(pack['admin/main.dart.js']!.protected, isTrue);
    expect(pack['web/main.dart.js']!.protected, isFalse);
  });

  test('a path nobody carries is null, not an exception', () {
    final DVAssetPack pack = place(dvWriteAssetPack(<DVAssetPackEntry>[DVAssetPackEntry('a.txt', text('a'))]));
    expect(pack['b.txt'], isNull);
    expect(pack['a.txt/'], isNull);
    expect(pack[''], isNull);
  });

  test('a range of a stored file is read by itself', () {
    final Uint8List video = Uint8List.fromList(List<int>.generate(1 << 20, (int i) => i & 0xff));
    final DVAssetPack pack = place(dvWriteAssetPack(<DVAssetPackEntry>[DVAssetPackEntry('clip.mp4', video)]));
    final DVPackedAsset asset = pack['clip.mp4']!;
    expect(pack.readStored(asset, start: 1000, end: 1010), video.sublist(1000, 1010));
    expect(pack.readStored(asset, start: video.length - 3), video.sublist(video.length - 3));
    expect(() => pack.readStored(asset, start: 5, end: video.length + 1), throwsRangeError);
  });

  test('the hash names the content, and the build id every file of it', () {
    Uint8List build(String body) => dvWriteAssetPack(<DVAssetPackEntry>[
          DVAssetPackEntry('index.html', text(body)),
          DVAssetPackEntry('same.js', text('same')),
        ]);
    final DVAssetPack a = place(build('one'));
    final String aHash = a['index.html']!.hash;
    final String aSame = a['same.js']!.hash;
    final String aBuild = a.buildId;
    final DVAssetPack b = place(build('two'));
    expect(b['index.html']!.hash, isNot(aHash));
    expect(b['same.js']!.hash, aSame);
    expect(b.buildId, isNot(aBuild));
    expect(place(build('one')).buildId, aBuild);
    // Short enough for a header, long enough never to collide by chance.
    expect(aHash, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('a path that would leave the site is refused when the pack is written', () {
    for (final String bad in <String>['../etc/passwd', '/abs', 'a/../../b', r'a\b', '']) {
      expect(() => dvWriteAssetPack(<DVAssetPackEntry>[DVAssetPackEntry(bad, text('x'))]),
          throwsArgumentError, reason: bad);
    }
  });

  test('bytes that are not a pack do not open', () {
    final File file = File(p.join(work.path, 'junk'))..writeAsBytesSync(List<int>.filled(512, 3));
    expect(DVAssetPack.open(file.path, offset: 0, length: 512), isNull);
    expect(DVAssetPack.open(file.path, offset: 400, length: 4000), isNull);
  });

  test('opening reads the index and none of the files', () {
    // A pack whose files are gone -- the data region cut off -- still opens
    // and still lists them: open touched nothing past the index.
    final Uint8List big = Uint8List.fromList(List<int>.generate(1 << 20, (int i) => i & 0xff));
    final Uint8List bytes = dvWriteAssetPack(<DVAssetPackEntry>[DVAssetPackEntry('big.bin', big)]);
    final File file = File(p.join(work.path, 'cut'))..writeAsBytesSync(bytes.sublist(0, bytes.length - big.length));
    final DVAssetPack? pack = DVAssetPack.open(file.path, offset: 0, length: bytes.length);
    expect(pack, isNotNull);
    expect(pack!['big.bin']!.size, big.length);
  });
}
