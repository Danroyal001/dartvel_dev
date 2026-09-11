// The web server resizes an image to a configured width, once, and refuses
// everything it should not do.
//
// NextFaster's images go through an optimizer that serves each at a fixed set
// of widths; a phone downloads the 640 and not the 3840. This is Dartvel's:
// `/_dartvel/image?src=...&w=...&q=...` on a web-server build. It is also an
// endpoint that reads files and fetches addresses on somebody else's say-so,
// so most of what is tested here is what it refuses.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_shelf/src/image_endpoint.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const DVImageVariants variants = DVImageVariants(
  endpoint: true,
  remoteHosts: <String>['cdn.example.com'],
);

List<int> png(int width, int height) => img.encodePng(
      img.fill(img.Image(width: width, height: height),
          color: img.ColorRgb8(200, 100, 50)),
    );

List<int> jpeg(int width, int height) => img.encodeJpg(
      img.fill(img.Image(width: width, height: height),
          color: img.ColorRgb8(20, 120, 220)),
    );

Future<List<int>> bytesOf(Response response) async => <int>[
      for (final List<int> chunk in await response.body!.stream.toList())
        ...chunk,
    ];

void main() {
  late Directory web;
  late Directory cache;
  late File outside;
  late List<Uri> fetched;

  setUp(() {
    final Directory root = Directory.systemTemp.createTempSync('dv_img_');
    addTearDown(() => root.deleteSync(recursive: true));
    web = Directory(p.join(root.path, 'web'))..createSync();
    cache = Directory(p.join(root.path, 'cache'));
    outside = File(p.join(root.path, 'outside.png'))
      ..writeAsBytesSync(png(800, 400));
    File(p.join(web.path, 'assets', 'assets', 'wide.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(png(1000, 500));
    File(p.join(web.path, 'assets', 'assets', 'photo.jpg'))
        .writeAsBytesSync(jpeg(1000, 500));
    File(p.join(web.path, 'assets', 'assets', 'small.png'))
        .writeAsBytesSync(png(300, 150));
    fetched = <Uri>[];
  });

  Future<Response?> ask(
    String src,
    Object width, {
    Map<String, String> headers = const <String, String>{},
    List<int>? remoteBody,
  }) {
    final Headers h = Headers();
    headers.forEach(h.set);
    return dvImageVariantResponse(
      Request(
        method: 'GET',
        url: Uri.parse('http://example.com/$dvImageEndpointPath'
            '?src=${Uri.encodeQueryComponent(src)}&w=$width'),
        headers: h,
        bodyStream: const Stream<List<int>>.empty(),
      ),
      webRoot: web.path,
      variants: variants,
      cacheDir: cache.path,
      fetchRemote: (Uri address) async {
        fetched.add(address);
        return remoteBody;
      },
    );
  }

  test('a request for anything else is not this endpoint\'s', () async {
    final Response? response = await dvImageVariantResponse(
      Request(
        method: 'GET',
        url: Uri.parse('http://example.com/assets/assets/wide.png'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      webRoot: web.path,
      variants: variants,
    );
    expect(response, isNull);
  });

  test('an image is resized to the width asked for', () async {
    final Response response = (await ask('assets/assets/wide.png', 640))!;

    expect(response.status, 200);
    expect(response.headers.get('content-type'), 'image/png');
    final img.Image out = img.decodeImage(
        Uint8List.fromList(await bytesOf(response)))!;
    expect(out.width, 640);
    expect(out.height, 320, reason: 'the aspect ratio is kept');
  });

  test('a PNG goes out as WebP to a browser that takes it', () async {
    final Response response = (await ask('assets/assets/wide.png', 640,
        headers: <String, String>{'accept': 'image/avif,image/webp,*/*'}))!;

    expect(response.headers.get('content-type'), 'image/webp');
    expect(img.decodeWebP(Uint8List.fromList(await bytesOf(response)))!.width, 640);
    // The same address answers differently by Accept, so a shared cache has
    // to keep the two apart.
    expect(response.headers.get('vary'), contains('Accept'));
  });

  test('a JPEG stays a JPEG even where WebP is accepted', () async {
    // The encoder only writes lossless WebP, which for a photograph is larger
    // than the JPEG it would replace.
    final Response response = (await ask('assets/assets/photo.jpg', 640,
        headers: <String, String>{'accept': 'image/webp'}))!;

    expect(response.headers.get('content-type'), 'image/jpeg');
    expect(img.decodeJpg(Uint8List.fromList(await bytesOf(response)))!.width, 640);
  });

  test('an image is never made larger than it is', () async {
    final Response response = (await ask('assets/assets/small.png', 640))!;

    expect(response.status, 200);
    expect(img.decodeImage(Uint8List.fromList(await bytesOf(response)))!.width, 300);
  });

  test('a width outside the set is refused', () async {
    expect((await ask('assets/assets/wide.png', 641))!.status, 400);
  });

  test('a path out of the site is refused', () async {
    expect((await ask('../outside.png', 640))!.status, 400);
    expect((await ask('assets/../../outside.png', 640))!.status, 400);
    expect((await ask(outside.path, 640))!.status, 400);
  });

  test('a link inside the site that points out of it is not followed',
      () async {
    Link(p.join(web.path, 'assets', 'assets', 'escape.png'))
        .createSync(outside.path);

    final Response response = (await ask('assets/assets/escape.png', 640))!;

    expect(response.status, 404);
  });

  test('an image that is not there is not found', () async {
    expect((await ask('assets/assets/missing.png', 640))!.status, 404);
  });

  test('a host nobody allowed is refused and never fetched', () async {
    final Response response = (await ask(
      'https://169.254.169.254/latest/meta-data.png',
      640,
      remoteBody: png(800, 400),
    ))!;

    expect(response.status, 400);
    expect(fetched, isEmpty);
  });

  test('an allowed host is fetched and resized', () async {
    final Response response = (await ask(
      'https://cdn.example.com/a.png',
      640,
      remoteBody: png(1200, 600),
    ))!;

    expect(fetched, <Uri>[Uri.parse('https://cdn.example.com/a.png')]);
    expect(response.status, 200);
    expect(img.decodeImage(Uint8List.fromList(await bytesOf(response)))!.width, 640);
  });

  test('an allowed host that answers with something not an image is a bad '
      'gateway, not a crash', () async {
    final Response response = (await ask(
      'https://cdn.example.com/a.png',
      640,
      remoteBody: 'this is not a picture'.codeUnits,
    ))!;

    expect(response.status, 502);
  });

  test('a variant is cached, and revalidates to 304', () async {
    final Response first = (await ask('assets/assets/wide.png', 640))!;
    await bytesOf(first);
    final String etag = first.headers.get('etag')!;
    expect(first.headers.get('cache-control'), contains('max-age='));
    expect(cache.listSync(recursive: true).whereType<File>(), isNotEmpty,
        reason: 'resized once, not on every request');

    final Response again = (await ask('assets/assets/wide.png', 640,
        headers: <String, String>{'if-none-match': etag}))!;
    expect(again.status, 304);

    final Response other = (await ask('assets/assets/wide.png', 750))!;
    expect(other.headers.get('etag'), isNot(etag),
        reason: 'another width is another variant');
  });

  test('the images section of the built manifest configures the server', () {
    File(p.join(web.path, 'dartvel_routes.json')).writeAsStringSync(
        '{"routes": {}, "images": {"widths": [320, 640], "quality": 60, '
        '"remoteHosts": ["cdn.example.com"], "endpoint": true}}');

    final DVImageVariants read = dvImageVariantsFor(web.path);

    expect(read.widths, <int>[320, 640]);
    expect(read.quality, 60);
    expect(read.allowsHost('cdn.example.com'), isTrue);
  });
}
