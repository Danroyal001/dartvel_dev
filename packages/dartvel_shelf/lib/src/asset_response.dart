/// A site file, answered.
///
/// A web-server binary keeps each file of its site the smallest way the
/// build found -- brotli for text, WebAssembly and fonts, as it is for a PNG
/// -- and reads it from the executable when it is asked for. A client that
/// accepts the kept encoding is sent those bytes untouched: nothing is
/// compressed per request. One that does not is sent the file decoded, which
/// happens once: the result is kept in memory when it is small and on disk
/// beside the server's data when it is not, under the build it came from, so
/// a new deploy never serves an old file.
///
/// Around that, what browsers and CDNs rely on: a strong ETag per encoding,
/// 304 for a match, single byte ranges (of the decoded file), `Vary:
/// Accept-Encoding` where the answer depends on it, and the `Cache-Control`
/// [DVAssetHttpPolicy] gives the file. A protected file is `private,
/// no-store` and is never kept by this cache either.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/framework.dart'
    show DVAssetEncoding, DVAssetFile, DVAssetHttpPolicy, DVAssetSource, dvAssetPath;
import 'package:dartvel_core/http.dart';
import 'package:dartvel_core/binary_payload.dart' show dvAssetWorthEncoding;

import 'mime_type.dart';

/// A body larger than this goes out in pieces of it, each a positioned read,
/// rather than as one read of the whole file.
const int _piece = 256 * 1024;

/// A file larger than this that had to be decoded is kept on disk rather
/// than decoded again; a smaller one costs less to decode than to read back.
const int _diskWorthy = 32 * 1024;

/// A file larger than this is not kept in memory: a few of them would push
/// out every small file that is asked for far more often.
const int _memoryEntryLimit = 512 * 1024;

/// What the server keeps of its site between requests.
final class DVAssetCache {
  DVAssetCache({this.memoryLimit = 16 * 1024 * 1024, this.directory, this.imagesDirectory});

  /// How many bytes of files may be held in memory.
  int memoryLimit;

  /// Whether decoded files are kept in [directory]. The site's declaration
  /// (`dartvel.web.server.http.diskCache`) can turn it off.
  bool diskEnabled = true;

  /// Where decoded files are kept on disk, one directory per build, or null
  /// for no disk cache. Safe to delete at any time: it is rebuilt on demand.
  final String? directory;

  /// Where resized images are kept, or null for the system's temporary
  /// directory. Not under [directory], whose other builds are removed: a
  /// variant is named by its source's bytes and outlives a deploy.
  final String? imagesDirectory;

  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap<String, Uint8List>();
  int _held = 0;

  /// The cache this process's server uses, when its entry point set one up.
  static DVAssetCache? current;

  /// How many files are held in memory.
  int get memoryEntries => _memory.length;

  /// How many bytes are held in memory.
  int get memoryBytes => _held;

  Uint8List? _recall(String key) {
    final Uint8List? kept = _memory.remove(key);
    if (kept != null) _memory[key] = kept; // most recently used last
    return kept;
  }

  void _remember(String key, Uint8List bytes) {
    if (bytes.length > _memoryEntryLimit || bytes.length > memoryLimit) return;
    final Uint8List? old = _memory.remove(key);
    if (old != null) _held -= old.length;
    _memory[key] = bytes;
    _held += bytes.length;
    while (_held > memoryLimit && _memory.isNotEmpty) {
      final String oldest = _memory.keys.first;
      _held -= _memory.remove(oldest)!.length;
    }
  }

  /// The directory [buildId]'s files are kept in, created, with every other
  /// build's removed: a deploy starts with nothing of the last one.
  Directory? forBuild(String buildId) {
    final String? root = directory;
    if (root == null) return null;
    final Directory mine = Directory('$root${Platform.pathSeparator}$buildId');
    if (_prepared.add(mine.path)) {
      try {
        mine.createSync(recursive: true);
        for (final FileSystemEntity other in Directory(root).listSync()) {
          if (other.path != mine.path) other.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // A cache that cannot be written is a slower server, not a broken one.
      }
    }
    return mine;
  }

  final Set<String> _prepared = <String>{};

  Uint8List? _fromDisk(String buildId, String hash) {
    if (!diskEnabled) return null;
    final Directory? dir = forBuild(buildId);
    if (dir == null) return null;
    final File file = File('${dir.path}${Platform.pathSeparator}$hash');
    try {
      return file.existsSync() ? file.readAsBytesSync() : null;
    } on FileSystemException {
      return null;
    }
  }

  void _toDisk(String buildId, String hash, Uint8List bytes) {
    if (!diskEnabled) return;
    final Directory? dir = forBuild(buildId);
    if (dir == null) return;
    try {
      // Written beside and renamed into place, so a request arriving mid-way
      // never reads half a file.
      final File partial = File('${dir.path}${Platform.pathSeparator}$hash.$pid.partial')
        ..writeAsBytesSync(bytes, flush: true);
      partial.renameSync('${dir.path}${Platform.pathSeparator}$hash');
    } on FileSystemException {
      // As above.
    }
  }
}

/// The response for [request] from [source], or null when the source has no
/// file at its path -- or the request is not a GET or HEAD -- and something
/// else should answer.
///
/// [transportCompresses] says the server compresses responses on the way
/// out, as dartvel_shelf's does unless it was turned off: a file sent as it
/// is may then reach the client gzipped, so its validator is weak and the
/// transport's own `Vary` covers it.
Future<Response?> dvAssetResponse(
  Request request,
  DVAssetSource source, {
  DVAssetHttpPolicy policy = const DVAssetHttpPolicy(),
  DVAssetCache? cache,
  bool transportCompresses = true,
}) async {
  final bool head = request.method == 'HEAD';
  if (!head && request.method != 'GET') return null;
  final String? path = dvAssetPath(request.url.path);
  if (path == null) return null;
  final DVAssetFile? file = source.file(path);
  if (file == null) return null;

  final bool protected = file.protected;
  final DVAssetEncoding kept = file.storedEncoding;
  final bool encoded = kept != DVAssetEncoding.identity;
  // Kept between requests only when the bytes are the build's own and not
  // per caller: a directory's files change under it, and a protected file is
  // never held where another caller's request could reach it.
  final String? buildId = protected ? null : source.buildId;
  final DVAssetCache? keep = buildId == null ? null : cache;

  final Headers headers = Headers()
    ..set('content-type', getMimeType(path))
    ..set('cache-control', policy.cacheControl(path, protected: protected));

  final bool sendKept = encoded && _accepts(request.headers.get('accept-encoding'), kept);
  // The transport compresses what goes out as it is when it is text of some
  // size, and says so in its own Vary.
  final bool transportVaries = transportCompresses && dvAssetWorthEncoding(path) && file.size >= 32;
  final String identityTag = transportVaries ? 'W/"${file.hash}"' : '"${file.hash}"';

  final String? condition = request.headers.get('if-none-match');
  if (condition != null && _matches(condition, file.hash)) {
    headers.set('etag', sendKept ? '"${file.hash}-${kept.token}"' : identityTag);
    if (encoded) headers.set('vary', 'Accept-Encoding');
    return Response(304, headers: headers, body: const Stream<List<int>>.empty());
  }

  // A range is of the file itself, never of an encoding of it.
  final String? rangeHeader = request.headers.get('range');
  if (rangeHeader != null && _rangeApplies(request.headers.get('if-range'), identityTag)) {
    final ({int start, int end})? range = _range(rangeHeader, file.size);
    if (range != null) {
      if (encoded) headers.set('vary', 'Accept-Encoding');
      if (range.start < 0) {
        headers.set('content-range', 'bytes */${file.size}');
        return Response(416, headers: headers, body: const Stream<List<int>>.empty());
      }
      final int length = range.end - range.start + 1;
      headers
        ..set('etag', identityTag)
        ..set('accept-ranges', 'bytes')
        ..set('content-range', 'bytes ${range.start}-${range.end}/${file.size}')
        ..set('content-length', '$length');
      final Stream<List<int>> bytes = head
          ? const Stream<List<int>>.empty()
          : encoded
              ? Stream<List<int>>.value(
                  Uint8List.sublistView(_decoded(file, keep, buildId), range.start, range.end + 1))
              : _pieces(file, range.start, range.end + 1);
      return Response(206, headers: headers, body: bytes);
    }
  }

  if (sendKept) {
    headers
      ..set('content-encoding', kept.token)
      ..set('vary', 'Accept-Encoding')
      ..set('etag', '"${file.hash}-${kept.token}"')
      ..set('content-length', '${file.storedLength}');
    if (head) return Response(200, headers: headers, body: const Stream<List<int>>.empty());
    return Response(200, headers: headers, body: _stored(file, keep, buildId));
  }

  headers
    ..set('etag', identityTag)
    ..set('accept-ranges', 'bytes')
    ..set('content-length', '${file.size}');
  if (encoded && !transportVaries) headers.set('vary', 'Accept-Encoding');
  if (head) return Response(200, headers: headers, body: const Stream<List<int>>.empty());
  if (encoded) {
    return Response(200, headers: headers, body: Stream<List<int>>.value(_decoded(file, keep, buildId)));
  }
  return Response(200, headers: headers, body: _stored(file, keep, buildId));
}

/// The file's kept bytes: from memory when they are there, else read -- in
/// pieces when the file is large.
Stream<List<int>> _stored(DVAssetFile file, DVAssetCache? keep, String? buildId) {
  final String key = '$buildId|${file.path}|${file.storedEncoding.token}';
  final Uint8List? held = keep?._recall(key);
  if (held != null) return Stream<List<int>>.value(held);
  if (file.storedLength > _piece) return _pieces(file, 0, file.storedLength);
  final Uint8List bytes = file.stored();
  keep?._remember(key, bytes);
  return Stream<List<int>>.value(bytes);
}

/// The file decoded: from memory, from disk, or decoded now and kept.
Uint8List _decoded(DVAssetFile file, DVAssetCache? keep, String? buildId) {
  final String key = '$buildId|${file.path}|identity';
  final Uint8List? held = keep?._recall(key);
  if (held != null) return held;
  final bool disk = keep != null && buildId != null && file.size >= _diskWorthy;
  Uint8List? bytes = disk ? keep._fromDisk(buildId, file.hash) : null;
  if (bytes == null || bytes.length != file.size) {
    bytes = file.bytes();
    if (disk) keep._toDisk(buildId, file.hash, bytes);
  }
  keep?._remember(key, bytes);
  return bytes;
}

/// [file]'s kept bytes from [start] to [end], a positioned read per piece,
/// each read only when the one before has been taken.
Stream<List<int>> _pieces(DVAssetFile file, int start, int end) async* {
  for (int at = start; at < end; at += _piece) {
    yield file.stored(start: at, end: at + _piece < end ? at + _piece : end);
  }
}

/// Whether `Accept-Encoding` [header] takes [encoding]: named with a
/// non-zero weight, or covered by `*` without being refused by name.
bool _accepts(String? header, DVAssetEncoding encoding) {
  if (header == null) return false;
  double? named;
  double? any;
  for (final String part in header.split(',')) {
    final List<String> fields = part.split(';');
    final String token = fields.first.trim().toLowerCase();
    double weight = 1;
    for (final String field in fields.skip(1)) {
      final String f = field.trim();
      if (f.startsWith('q=')) weight = double.tryParse(f.substring(2)) ?? 0;
    }
    if (token == encoding.token) named = weight;
    if (token == '*') any = weight;
  }
  return (named ?? any ?? 0) > 0;
}

/// Whether `If-None-Match` [condition] names this file in any encoding. The
/// weak comparison, as a 304 uses: the same content is the same file however
/// it was sent.
bool _matches(String condition, String hash) {
  for (final String raw in condition.split(',')) {
    String tag = raw.trim();
    if (tag == '*') return true;
    if (tag.startsWith('W/')) tag = tag.substring(2);
    if (tag.length < 2 || !tag.startsWith('"') || !tag.endsWith('"')) continue;
    final String value = tag.substring(1, tag.length - 1);
    if (value == hash || value.startsWith('$hash-')) return true;
  }
  return false;
}

/// Whether a range may be answered: no `If-Range`, or one that is this
/// file's current strong tag. A date or a weak tag is not enough to stitch
/// pieces of two versions together, so either is the whole file.
bool _rangeApplies(String? ifRange, String identityTag) =>
    ifRange == null || (!identityTag.startsWith('W/') && ifRange.trim() == identityTag);

/// The one byte range [header] asks for in a file of [size] bytes; start -1
/// for one that cannot be satisfied; null for a header this does not answer
/// with a range -- several ranges, another unit, or not a range at all --
/// which is answered with the whole file.
({int start, int end})? _range(String header, int size) {
  final RegExpMatch? m = RegExp(r'^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$').firstMatch(header);
  if (m == null) return null;
  final String first = m.group(1)!;
  final String last = m.group(2)!;
  if (first.isEmpty && last.isEmpty) return null;
  if (first.isEmpty) {
    final int suffix = int.parse(last);
    if (suffix == 0 || size == 0) return (start: -1, end: -1);
    return (start: suffix >= size ? 0 : size - suffix, end: size - 1);
  }
  final int start = int.parse(first);
  final int? end = last.isEmpty ? null : int.parse(last);
  if (end != null && end < start) return null;
  if (start >= size) return (start: -1, end: -1);
  return (start: start, end: end == null || end >= size ? size - 1 : end);
}
