// A site file, answered: in the encoding it is kept in when the client takes
// it, decoded once when it does not, with the validators, ranges and cache
// directives a browser and a CDN need.
//
// Against a pack kept the way a web-server build keeps one -- brotli from the
// committed native library -- since that is what a binary serves from.
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_core/dartvel.dart' show Headers, Request, Response;
import 'package:dartvel_core/framework.dart' show DVAssetHttpPolicy;
import 'package:dartvel_shelf/src/asset_response.dart';
import 'package:dartvel_shelf/src/native_codec.dart';
import 'package:dartvel_shelf/src/native_library.dart' show nativeServerLibraryLocation;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Request request(String path, {String method = 'GET', Map<String, String> headers = const <String, String>{}}) =>
    Request(
      method: method,
      url: Uri.parse('http://localhost$path'),
      headers: Headers(headers),
      bodyStream: const Stream<List<int>>.empty(),
    );

Future<Uint8List> body(Response response) async {
  final BytesBuilder out = BytesBuilder(copy: false);
  await for (final List<int> chunk in response.body!.stream) {
    out.add(chunk);
  }
  return out.takeBytes();
}

void main() {
  late Directory work;
  late DVNativeCodec codec;
  late DVAssetSource site;
  late DVAssetSource studio;

  final Uint8List js = Uint8List.fromList(utf8.encode(
      List<String>.generate(4000, (int i) => 'function f$i(){return $i}').join('\n')));
  final Random random = Random(3);
  final Uint8List png = Uint8List.fromList(
      <int>[0x89, 0x50, 0x4e, 0x47, ...List<int>.generate(3 << 20, (_) => random.nextInt(256))]);
  final Uint8List html = Uint8List.fromList(utf8.encode('<!doctype html><title>Home</title>' * 20));

  setUpAll(() {
    final ({String subdir, String name}) location = nativeServerLibraryLocation();
    codec = DVNativeCodec.of(ffi.DynamicLibrary.open('lib/native/${location.subdir}/${location.name}'))!
      ..registerDecoders();
  });

  setUp(() {
    work = Directory.systemTemp.createTempSync('dv_asset_response_');
    DVAssetPackEntry br(String path, Uint8List bytes, {bool protected = false}) => DVAssetPackEntry(
        path, bytes, stored: codec.encode(DVAssetEncoding.br, bytes), encoding: DVAssetEncoding.br, protected: protected);
    final Uint8List bytes = dvWriteAssetPack(<DVAssetPackEntry>[
      br('web/main.dart.js', js),
      br('web/index.html', html),
      br('web/app.3f2a9c1b.js', js),
      DVAssetPackEntry('web/big.png', png),
      br('admin/main.dart.js', js, protected: true),
    ]);
    final File server = File(p.join(work.path, 'server'))..writeAsBytesSync(bytes);
    final DVAssetPack pack = DVAssetPack.open(server.path, offset: 0, length: bytes.length)!;
    site = DVPackedAssets(pack, prefix: 'web/');
    studio = DVPackedAssets(pack, prefix: 'admin/');
  });
  tearDown(() => work.deleteSync(recursive: true));

  Future<Response> ask(String path,
          {String method = 'GET',
          Map<String, String> headers = const <String, String>{},
          DVAssetSource? from,
          DVAssetCache? cache,
          bool transportCompresses = true}) async =>
      (await dvAssetResponse(request(path, method: method, headers: headers), from ?? site,
          cache: cache, transportCompresses: transportCompresses))!;

  group('encoding', () {
    test('a client that takes brotli is sent the bytes as kept', () async {
      final Response r = await ask('/main.dart.js', headers: <String, String>{'accept-encoding': 'gzip, deflate, br, zstd'});
      expect(r.status, 200);
      expect(r.headers.get('content-encoding'), 'br');
      expect(r.headers.get('vary'), 'Accept-Encoding');
      expect(r.headers.get('content-type'), contains('javascript'));
      final Uint8List sent = await body(r);
      expect(r.headers.get('content-length'), '${sent.length}');
      expect(sent.length, lessThan(js.length ~/ 5));
      expect(codec.decode(DVAssetEncoding.br, sent, js.length), js);
      expect(r.headers.get('etag'), matches(RegExp(r'^"[0-9a-f]{32}-br"$')));
      expect(r.headers.get('accept-ranges'), isNull, reason: 'ranges are of the decoded file');
    });

    test('a client that does not is sent the file itself', () async {
      for (final String? accepts in <String?>[null, 'gzip, deflate', 'br;q=0, gzip', 'identity']) {
        final Response r = await ask('/main.dart.js',
            headers: <String, String>{if (accepts != null) 'accept-encoding': accepts});
        expect(r.headers.get('content-encoding'), isNull, reason: '$accepts');
        expect(await body(r), js, reason: '$accepts');
        expect(r.headers.get('accept-ranges'), 'bytes');
        // The transport may gzip it on the way out, so the validator is
        // weak, and the transport's own Vary covers it.
        expect(r.headers.get('etag'), matches(RegExp(r'^W/"[0-9a-f]{32}"$')));
        expect(r.headers.get('vary'), isNull);
      }
    });

    test('without a compressing transport the file itself is strong and still varies', () async {
      final Response r = await ask('/main.dart.js', transportCompresses: false);
      expect(r.headers.get('etag'), matches(RegExp(r'^"[0-9a-f]{32}"$')));
      expect(r.headers.get('vary'), 'Accept-Encoding');
    });

    test('a wildcard takes the kept encoding', () async {
      expect((await ask('/main.dart.js', headers: <String, String>{'accept-encoding': '*'})).headers.get('content-encoding'), 'br');
      expect((await ask('/main.dart.js', headers: <String, String>{'accept-encoding': '*, br;q=0'})).headers.get('content-encoding'), isNull);
    });

    test('a file kept as it is goes as it is to everybody, and does not vary', () async {
      final Response r = await ask('/big.png', headers: <String, String>{'accept-encoding': 'br'});
      expect(r.headers.get('content-encoding'), isNull);
      expect(r.headers.get('vary'), isNull);
      expect(r.headers.get('etag'), matches(RegExp(r'^"[0-9a-f]{32}"$')));
      expect(await body(r), png);
    });

    test('a large file goes in pieces, not as one read of all of it', () async {
      final Response r = await ask('/big.png');
      final List<int> sizes = <int>[await for (final List<int> chunk in r.body!.stream) chunk.length];
      expect(sizes.length, greaterThan(1));
      expect(sizes.reduce(max), lessThanOrEqualTo(512 * 1024));
      expect(sizes.reduce((int a, int b) => a + b), png.length);
      expect(r.headers.get('content-length'), '${png.length}');
    });
  });

  group('revalidation', () {
    test('a matching ETag is a 304 with no body', () async {
      final Response first = await ask('/main.dart.js', headers: <String, String>{'accept-encoding': 'br'});
      final String etag = first.headers.get('etag')!;
      final Response again = await ask('/main.dart.js',
          headers: <String, String>{'accept-encoding': 'br', 'if-none-match': etag});
      expect(again.status, 304);
      expect(await body(again), isEmpty);
      expect(again.headers.get('etag'), etag);
      expect(again.headers.get('cache-control'), 'public, no-cache');
      expect(again.headers.get('vary'), 'Accept-Encoding');
    });

    test('the tag of the other encoding, a weak tag, a list and a star all match', () async {
      final String hash = RegExp(r'[0-9a-f]{32}').firstMatch(
          (await ask('/main.dart.js')).headers.get('etag')!)!.group(0)!;
      for (final String condition in <String>['"$hash"', 'W/"$hash"', '"$hash-br"', '"x", "$hash-br"', '*']) {
        final Response r = await ask('/main.dart.js', headers: <String, String>{'if-none-match': condition});
        expect(r.status, 304, reason: condition);
      }
      expect((await ask('/main.dart.js', headers: <String, String>{'if-none-match': '"other"'})).status, 200);
    });
  });

  group('ranges', () {
    test('decimal ranges larger than a machine integer do not crash the request', () async {
      const String huge = '999999999999999999999999999999999999999999';
      for (final String range in <String>['bytes=$huge-', 'bytes=0-$huge', 'bytes=-$huge']) {
        final Response r = await ask('/big.png', headers: <String, String>{'range': range});
        expect(r.status, 200, reason: range);
        expect(r.headers.get('content-range'), isNull);
        expect(await body(r), png);
      }
    });

    test('a range of a file kept as it is', () async {
      final Response r = await ask('/big.png', headers: <String, String>{'range': 'bytes=100-199'});
      expect(r.status, 206);
      expect(r.headers.get('content-range'), 'bytes 100-199/${png.length}');
      expect(r.headers.get('content-length'), '100');
      expect(await body(r), png.sublist(100, 200));
    });

    test('a range of a file kept encoded is of the file itself', () async {
      final Response r = await ask('/main.dart.js',
          headers: <String, String>{'range': 'bytes=10-19', 'accept-encoding': 'br'});
      expect(r.status, 206);
      expect(r.headers.get('content-encoding'), isNull);
      expect(await body(r), js.sublist(10, 20));
      expect(r.headers.get('vary'), 'Accept-Encoding');
    });

    test('open-ended and suffix ranges', () async {
      expect(await body(await ask('/big.png', headers: <String, String>{'range': 'bytes=${png.length - 5}-'})),
          png.sublist(png.length - 5));
      final Response suffix = await ask('/big.png', headers: <String, String>{'range': 'bytes=-7'});
      expect(suffix.headers.get('content-range'), 'bytes ${png.length - 7}-${png.length - 1}/${png.length}');
      expect(await body(suffix), png.sublist(png.length - 7));
    });

    test('a range past the end is a 416 that says how long the file is', () async {
      final Response r = await ask('/big.png', headers: <String, String>{'range': 'bytes=${png.length}-'});
      expect(r.status, 416);
      expect(r.headers.get('content-range'), 'bytes */${png.length}');
    });

    test('several ranges, a malformed one, or a stale If-Range get the whole file', () async {
      final String etag = (await ask('/big.png')).headers.get('etag')!;
      for (final Map<String, String> h in <Map<String, String>>[
        <String, String>{'range': 'bytes=0-1,5-6'},
        <String, String>{'range': 'lines=1-2'},
        <String, String>{'range': 'bytes=9-3'},
        <String, String>{'range': 'bytes=0-9', 'if-range': '"stale"'},
      ]) {
        final Response r = await ask('/big.png', headers: h);
        expect(r.status, 200, reason: '$h');
      }
      final Response current = await ask('/big.png', headers: <String, String>{'range': 'bytes=0-9', 'if-range': etag});
      expect(current.status, 206);
    });
  });

  group('cache directives', () {
    test('by what the file is', () async {
      expect((await ask('/main.dart.js')).headers.get('cache-control'), 'public, no-cache');
      expect((await ask('/app.3f2a9c1b.js')).headers.get('cache-control'), 'public, max-age=31536000, immutable');
      expect((await ask('/index.html')).headers.get('cache-control'), 'no-cache');
    });

    test('a protected file is private and never stored', () async {
      final Response r = await ask('/main.dart.js', from: studio, headers: <String, String>{'accept-encoding': 'br'});
      expect(r.headers.get('cache-control'), 'private, no-store');
      expect(r.headers.get('content-encoding'), 'br');
    });
  });

  test('HEAD has the headers and no body', () async {
    final Response r = await ask('/big.png', method: 'HEAD');
    expect(r.status, 200);
    expect(r.headers.get('content-length'), '${png.length}');
    expect(await body(r), isEmpty);
  });

  test('a path the site does not have, or leaves it, is not answered here', () async {
    for (final String path in <String>['/missing.js', '/', '/../admin/main.dart.js', '/%2e%2e/admin/main.dart.js']) {
      expect(await dvAssetResponse(request(path), site), isNull, reason: path);
    }
    expect(await dvAssetResponse(request('/main.dart.js', method: 'POST'), site), isNull);
  });

  group('the server\'s own cache', () {
    test('keeps a small file in memory, and a protected one never', () async {
      final DVAssetCache cache = DVAssetCache(memoryLimit: 1 << 20);
      await body(await ask('/main.dart.js', cache: cache, headers: <String, String>{'accept-encoding': 'br'}));
      expect(cache.memoryEntries, 1);
      await body(await ask('/main.dart.js', from: studio, cache: cache, headers: <String, String>{'accept-encoding': 'br'}));
      await body(await ask('/main.dart.js', from: studio, cache: cache));
      expect(cache.memoryEntries, 1);
      expect(cache.memoryBytes, lessThanOrEqualTo(1 << 20));
    });

    test('drops the least recently used when it is full', () async {
      final DVAssetCache cache = DVAssetCache(memoryLimit: js.length + 10);
      await body(await ask('/main.dart.js', cache: cache));
      await body(await ask('/index.html', cache: cache));
      expect(cache.memoryBytes, lessThanOrEqualTo(js.length + 10));
      expect(cache.memoryEntries, 1);
    });

    test('keeps a decoded file on disk under the build, and never a protected one', () async {
      final Directory dir = Directory(p.join(work.path, 'cache'));
      final DVAssetCache cache = DVAssetCache(memoryLimit: 0, directory: dir.path);
      expect(await body(await ask('/main.dart.js', cache: cache)), js);
      final List<File> kept = dir.listSync(recursive: true).whereType<File>().toList();
      expect(kept, hasLength(1));
      expect(p.split(kept.single.path), contains(site.buildId));
      expect(kept.single.readAsBytesSync(), js);
      // Served from there the next time, by a server that never decoded it.
      final DVAssetCache fresh = DVAssetCache(memoryLimit: 0, directory: dir.path);
      expect(await body(await ask('/main.dart.js', cache: fresh)), js);
      await body(await ask('/main.dart.js', from: studio, cache: cache));
      expect(dir.listSync(recursive: true).whereType<File>(), hasLength(1));
    });

    test('a directory left by another build is removed', () {
      final Directory dir = Directory(p.join(work.path, 'cache'));
      Directory(p.join(dir.path, 'old-build')).createSync(recursive: true);
      DVAssetCache(memoryLimit: 0, directory: dir.path).forBuild(site.buildId!);
      expect(Directory(p.join(dir.path, 'old-build')).existsSync(), isFalse);
      expect(Directory(p.join(dir.path, site.buildId)).existsSync(), isTrue);
    });
  });
}
