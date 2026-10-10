// The disk cache behind every player on a target with a filesystem.
//
// A player opens a loopback address; the cache answers it from disk where it
// has the bytes and from the origin where it does not, keeping what it
// fetches. The failures here are quiet ones: a cached file served short and
// played as if it ended early, a range answered from the wrong offset and
// decoded as noise, a cache that grows until the device is full, and a
// "precached" video that still waits on the network for its first frame.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// An origin that counts what it was asked for.
final class _Origin {
  _Origin(this.server, this.bytes, {required this.ranges});

  final HttpServer server;
  final Uint8List bytes;
  final bool ranges;
  final List<String?> requests = <String?>[];

  int get bytesSent => _sent;
  int _sent = 0;

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  static Future<_Origin> start(int length, {bool ranges = true}) async {
    final Uint8List bytes =
        Uint8List.fromList(List<int>.generate(length, (int i) => i % 251));
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final _Origin origin = _Origin(server, bytes, ranges: ranges);
    server.listen(origin._serve);
    return origin;
  }

  Future<void> _serve(HttpRequest request) async {
    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    requests.add(range);
    final HttpResponse response = request.response;
    response.headers.contentType = ContentType('video', 'mp4');
    if (request.uri.path == '/missing') {
      response.statusCode = 404;
      await response.close();
      return;
    }
    int start = 0;
    int end = bytes.length - 1;
    if (ranges && range != null) {
      final RegExpMatch m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range)!;
      start = int.parse(m.group(1)!);
      if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
      if (end >= bytes.length) end = bytes.length - 1;
      response.statusCode = 206;
      response.headers
          .set('content-range', 'bytes $start-$end/${bytes.length}');
    }
    if (ranges) response.headers.set('accept-ranges', 'bytes');
    response.contentLength = end - start + 1;
    if (request.method != 'HEAD') {
      response.add(bytes.sublist(start, end + 1));
      _sent += end - start + 1;
    }
    await response.close();
  }

  Future<void> close() => server.close(force: true);
}

Future<(int, Map<String, String>, Uint8List)> _get(String url,
    {String? range}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final HttpClientResponse response = await request.close();
    final BytesBuilder body = BytesBuilder();
    await response.forEach(body.add);
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      headers[name] = values.join(',');
    });
    return (response.statusCode, headers, body.takeBytes());
  } finally {
    client.close(force: true);
  }
}

void main() {
  late Directory dir;
  late _Origin origin;
  late DVDiskMediaCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dv-media-cache-');
    origin = await _Origin.start(200000);
    cache = DVDiskMediaCache(dir.path, maxBytes: 1 << 20);
  });

  tearDown(() async {
    await cache.close();
    await origin.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('a player reads the whole file through the cache, once from origin',
      () async {
    final String address = await cache.playbackAddress(origin.url('/a.mp4'));
    expect(Uri.parse(address).host, '127.0.0.1');

    final (int status, _, Uint8List first) = await _get(address);
    expect(status, 200);
    expect(first, origin.bytes);
    final int fetched = origin.bytesSent;
    expect(fetched, origin.bytes.length);

    final (int again, _, Uint8List second) = await _get(address);
    expect(again, 200);
    expect(second, origin.bytes);
    // The second read came off disk.
    expect(origin.bytesSent, fetched);
    expect(await cache.contains(origin.url('/a.mp4')), isTrue);
  });

  test('a range is answered from the right offset with the right headers',
      () async {
    final String address = await cache.playbackAddress(origin.url('/a.mp4'));
    await _get(address); // fill

    final (int status, Map<String, String> headers, Uint8List part) =
        await _get(address, range: 'bytes=1000-1999');
    expect(status, 206);
    expect(headers['content-range'], 'bytes 1000-1999/200000');
    expect(headers['content-length'], '1000');
    expect(part, origin.bytes.sublist(1000, 2000));
  });

  test('a seek past what is cached goes to origin and is still correct',
      () async {
    await cache.precache(origin.url('/a.mp4'), bytes: 5000);
    final String address = await cache.playbackAddress(origin.url('/a.mp4'));
    origin.requests.clear();

    final (int status, _, Uint8List part) =
        await _get(address, range: 'bytes=150000-');
    expect(status, 206);
    expect(part, origin.bytes.sublist(150000));
    expect(origin.requests, <String?>['bytes=150000-199999']);
  });

  test('a read that starts inside the cached prefix continues from origin',
      () async {
    await cache.precache(origin.url('/a.mp4'), bytes: 5000);
    origin.requests.clear();
    final String address = await cache.playbackAddress(origin.url('/a.mp4'));

    final (int status, _, Uint8List body) = await _get(address);
    expect(status, 200);
    expect(body, origin.bytes);
    // Only what was not on disk was fetched.
    expect(origin.requests, <String?>['bytes=5000-199999']);
    expect(await cache.contains(origin.url('/a.mp4')), isTrue);
  });

  test('precache fetches the first bytes so the start needs no network',
      () async {
    await cache.precache(origin.url('/a.mp4'), bytes: 64 * 1024);
    expect(await cache.contains(origin.url('/a.mp4'), bytes: 64 * 1024),
        isTrue);
    expect(await cache.contains(origin.url('/a.mp4')), isFalse);
    origin.requests.clear();

    final String address = await cache.playbackAddress(origin.url('/a.mp4'));
    final (int status, _, Uint8List head) =
        await _get(address, range: 'bytes=0-65535');
    expect(status, 206);
    expect(head, origin.bytes.sublist(0, 65536));
    expect(origin.requests, isEmpty);
  });

  test('precaching the same URL twice at once fetches it once', () async {
    await Future.wait(<Future<void>>[
      cache.precache(origin.url('/a.mp4')),
      cache.precache(origin.url('/a.mp4')),
    ]);
    expect(origin.bytesSent, origin.bytes.length);
  });

  test('the least recently used entries go when the cache is full', () async {
    final DVDiskMediaCache small = DVDiskMediaCache(
        '${dir.path}/small', maxBytes: 450000);
    addTearDown(small.close);
    await small.precache(origin.url('/one.mp4'));
    await small.precache(origin.url('/two.mp4'));
    // Touch one, so two is the oldest.
    await small.playbackAddress(origin.url('/one.mp4'));
    await small.precache(origin.url('/three.mp4'));

    expect(await small.size(), lessThanOrEqualTo(450000));
    expect(await small.contains(origin.url('/one.mp4')), isTrue);
    expect(await small.contains(origin.url('/two.mp4')), isFalse);
    expect(await small.contains(origin.url('/three.mp4')), isTrue);
  });

  test('an origin that ignores ranges is still read correctly', () async {
    final _Origin plain = await _Origin.start(30000, ranges: false);
    addTearDown(plain.close);
    await cache.precache(plain.url('/p.mp4'), bytes: 1000);
    final String address = await cache.playbackAddress(plain.url('/p.mp4'));
    final (int status, _, Uint8List body) = await _get(address);
    expect(status, 200);
    expect(body, plain.bytes);
  });

  test('an origin error reaches the player as that error, and caches nothing',
      () async {
    final String address =
        await cache.playbackAddress(origin.url('/missing'));
    final (int status, _, _) = await _get(address);
    expect(status, 404);
    expect(await cache.contains(origin.url('/missing'), bytes: 1), isFalse);
  });

  test('precache of a missing file fails', () async {
    await expectLater(
        cache.precache(origin.url('/missing')), throwsA(isA<HttpException>()));
  });

  test('clear empties it', () async {
    await cache.precache(origin.url('/a.mp4'));
    expect(await cache.size(), origin.bytes.length);
    await cache.clear();
    expect(await cache.size(), 0);
    expect(await cache.contains(origin.url('/a.mp4'), bytes: 1), isFalse);
  });

  test('what is cached survives a new cache over the same directory',
      () async {
    await cache.precache(origin.url('/a.mp4'));
    await cache.close();
    cache = DVDiskMediaCache(dir.path, maxBytes: 1 << 20);
    expect(await cache.contains(origin.url('/a.mp4')), isTrue);
    final int before = origin.bytesSent;
    final (_, _, Uint8List body) =
        await _get(await cache.playbackAddress(origin.url('/a.mp4')));
    expect(body, origin.bytes);
    expect(origin.bytesSent, before);
  });

  test('only http and https are proxied', () async {
    expect(await cache.playbackAddress('file:///tmp/a.mp4'),
        'file:///tmp/a.mp4');
    expect(await cache.playbackAddress('rtsp://cam/stream'),
        'rtsp://cam/stream');
  });
}
