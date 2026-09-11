/// Resized images for a web-server build: `/_dartvel/image?src=&w=&q=`.
///
/// NextFaster's images go through an optimizer that serves each at a fixed
/// set of widths, so a phone downloads the 640 and not the 3840. This is
/// Dartvel's. It reads files and fetches addresses on somebody else's say-so,
/// which is why most of it is about what it refuses: a width outside the
/// configured set, a path that leaves the site (by `..` or by a link), a host
/// the application did not allow, and a redirect from an allowed host to one
/// it did not.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Fetches a remote image's bytes, or null when it cannot be had.
typedef DVRemoteImageFetch = Future<List<int>?> Function(Uri address);

/// Larger than any image a page should be serving, and small enough that a
/// request for one cannot exhaust the server.
const int _maxSourceBytes = 25 * 1024 * 1024;

/// The response to a variant request, or null when [request] is not one.
///
/// [webRoot] is the built site: local sources are read from it and from
/// nowhere else. [cacheDir] keeps each variant once it is made, so the image
/// is resized on the first request for it and read on every one after.
Future<Response?> dvImageVariantResponse(
  Request request, {
  required String webRoot,
  required DVImageVariants variants,
  DVRemoteImageFetch? fetchRemote,
  String? cacheDir,
}) async {
  // Only where the build said there is one: a server whose application
  // configured no variants answers this address as it answers any other.
  if (!variants.endpoint) return null;
  final String path = request.url.path.startsWith('/')
      ? request.url.path.substring(1)
      : request.url.path;
  if (path != dvImageEndpointPath) return null;
  if (request.method != 'GET' && request.method != 'HEAD') {
    return _text(405, 'images are fetched with GET');
  }

  final ({DVImageVariantRequest? request, String? refusal}) parsed =
      DVImageVariantRequest.parse(request.url.queryParameters, variants);
  final DVImageVariantRequest? asked = parsed.request;
  if (asked == null) return _text(400, parsed.refusal!);

  final List<int>? source;
  final Uri? remote = asked.remote;
  if (remote != null) {
    source = await (fetchRemote ?? _fetch)(remote);
    if (source == null) return _text(502, 'the image could not be fetched');
  } else {
    final File? file = _inside(webRoot, asked.src);
    if (file == null) return _text(404, 'no such image');
    source = await file.readAsBytes();
  }
  if (source.length > _maxSourceBytes) {
    return _text(remote == null ? 413 : 502, 'the image is too large');
  }

  final Uint8List bytes = source is Uint8List ? source : Uint8List.fromList(source);
  final img.ImageFormat format = img.findFormatForData(bytes);
  if (format == img.ImageFormat.invalid) {
    return _text(remote == null ? 415 : 502, 'that is not an image');
  }
  final bool acceptsWebP =
      (request.headers.get('accept') ?? '').contains('image/webp');
  final String out = _outputFormat(format, acceptsWebP: acceptsWebP);

  // Keyed on the source's bytes, so a changed image is a different variant
  // whatever its address, and a revalidation costs a hash rather than a
  // resize.
  final String etag =
      '"${sha1.convert(bytes).toString().substring(0, 20)}-${asked.width}'
      '-${asked.quality}-$out"';
  final Headers headers = Headers()
    ..set('etag', etag)
    // A day fresh and a week stale-while-revalidate: the address does not
    // change when the image does, so an immutable year would pin an old
    // image in every browser that had it. The ETag makes revalidating cheap.
    ..set('cache-control', 'public, max-age=86400, stale-while-revalidate=604800');
  // A PNG answers WebP or PNG by Accept, so a shared cache has to keep the
  // two apart. Nothing else varies.
  if (format == img.ImageFormat.png || format == img.ImageFormat.webp) {
    headers.set('vary', 'Accept');
  }
  if (request.headers.get('if-none-match') == etag) {
    return Response(304, headers: headers, body: const Stream<List<int>>.empty());
  }

  final Uint8List? variant = await _variant(
    bytes,
    width: asked.width,
    quality: asked.quality,
    format: out,
    cache: cacheDir == null
        ? null
        : File(p.join(cacheDir, '${sha1.convert(utf8.encode(etag))}.$out')),
  );
  if (variant == null) {
    return _text(remote == null ? 415 : 502, 'the image could not be read');
  }

  headers
    ..set('content-type', 'image/$out')
    ..set('content-length', '${variant.length}');
  return Response(
    200,
    headers: headers,
    body: request.method == 'HEAD'
        ? const Stream<List<int>>.empty()
        : Stream<List<int>>.value(variant),
  );
}

/// The `dartvel.images` the build wrote into `dartvel_routes.json`, read
/// once per change of the file.
DVImageVariants dvImageVariantsFor(String webRoot) {
  final File manifest = File(p.join(webRoot, 'dartvel_routes.json'));
  if (!manifest.existsSync()) return const DVImageVariants();
  final DateTime modified = manifest.lastModifiedSync();
  final ({DateTime modified, DVImageVariants variants})? known =
      _configs[manifest.path];
  if (known != null && known.modified == modified) return known.variants;
  DVImageVariants variants = const DVImageVariants();
  try {
    final Object? decoded = jsonDecode(manifest.readAsStringSync());
    if (decoded is Map) variants = DVImageVariants.fromJson(decoded['images']);
  } on FormatException {
    // A manifest that is not JSON serves no variants rather than failing
    // every request.
  }
  _configs[manifest.path] = (modified: modified, variants: variants);
  return variants;
}

final Map<String, ({DateTime modified, DVImageVariants variants})> _configs =
    <String, ({DateTime modified, DVImageVariants variants})>{};

/// Where [webRoot]'s variants are kept: under the system's temporary
/// directory, one folder per site, because the site itself may be deployed
/// read-only and a cache that cannot be written only makes the server slower.
String dvImageVariantCacheDir(String webRoot) => p.join(
      Directory.systemTemp.path,
      'dartvel_image_variants',
      sha1.convert(utf8.encode(p.canonicalize(webRoot))).toString().substring(0, 16),
    );

/// What a source goes out as.
///
/// The encoder writes only lossless WebP: smaller than a PNG, larger than a
/// JPEG of a photograph. So a PNG becomes WebP for a browser that takes it,
/// a JPEG stays a JPEG, and a GIF is passed through untouched -- resizing it
/// would keep only the first frame of an animation.
String _outputFormat(img.ImageFormat source, {required bool acceptsWebP}) =>
    switch (source) {
      img.ImageFormat.jpg => 'jpeg',
      img.ImageFormat.gif => 'gif',
      img.ImageFormat.png || img.ImageFormat.webp =>
        acceptsWebP ? 'webp' : 'png',
      _ => 'png',
    };

Future<Uint8List?> _variant(
  Uint8List source, {
  required int width,
  required int quality,
  required String format,
  File? cache,
}) async {
  if (cache != null && cache.existsSync()) return cache.readAsBytes();
  if (format == 'gif') return source;
  // Off the event loop: a large image takes long enough to decode that the
  // server would stop answering everybody else while it did.
  final Uint8List? made = await Isolate.run(
      () => _resize(source, width: width, quality: quality, format: format));
  if (made != null && cache != null) {
    try {
      cache.parent.createSync(recursive: true);
      // Written beside and renamed into place, so a request arriving mid-way
      // never reads half a file.
      final File partial = File('${cache.path}.$pid.partial')
        ..writeAsBytesSync(made, flush: true);
      partial.renameSync(cache.path);
    } on FileSystemException {
      // A cache that cannot be written is a slower server, not a broken one.
    }
  }
  return made;
}

Uint8List? _resize(
  Uint8List source, {
  required int width,
  required int quality,
  required String format,
}) {
  final img.Image? decoded = img.decodeImage(source);
  if (decoded == null) return null;
  // Never larger than it is: an upscaled copy is bigger and no sharper.
  final img.Image sized = decoded.width > width
      ? img.copyResize(decoded,
          width: width, interpolation: img.Interpolation.average)
      : decoded;
  return switch (format) {
    'jpeg' => img.encodeJpg(sized, quality: quality),
    'webp' => img.encodeWebP(sized),
    _ => img.encodePng(sized),
  };
}

/// [src] under [webRoot], or null when it is not there or is not really
/// there: a link inside the site that points out of it is refused as
/// firmly as `..`, because following it serves whatever it points at.
File? _inside(String webRoot, String src) {
  final String root;
  try {
    root = Directory(webRoot).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
  final String candidate = p.normalize(p.join(root, src));
  if (!p.isWithin(root, candidate)) return null;
  final File file = File(candidate);
  if (!file.existsSync()) return null;
  try {
    if (!p.isWithin(root, file.resolveSymbolicLinksSync())) return null;
  } on FileSystemException {
    return null;
  }
  return file;
}

/// The default fetch: no redirects, a timeout, and a size limit.
///
/// Redirects are not followed because the allowlist names the host that was
/// asked, and a redirect from it to one that was not allowed would be the
/// same hole the allowlist exists to close.
Future<List<int>?> _fetch(Uri address) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final HttpClientRequest request = await client.getUrl(address)
      ..followRedirects = false;
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final BytesBuilder body = BytesBuilder(copy: false);
    await for (final List<int> chunk
        in response.timeout(const Duration(seconds: 20))) {
      body.add(chunk);
      if (body.length > _maxSourceBytes) return null;
    }
    return body.takeBytes();
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

Response _text(int status, String message) => Response(
      status,
      headers: Headers()
        ..set('content-type', 'text/plain; charset=utf-8')
        ..set('cache-control', 'no-store'),
      body: Stream<List<int>>.value(utf8.encode(message)),
    );
