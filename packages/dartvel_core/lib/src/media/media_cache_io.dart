/// The disk cache, as a loopback HTTP server over a directory.
///
/// Each URL is two files named by the SHA-256 of the URL: `<key>.data`, the
/// bytes from the start of the file up to as far as anything has read, and
/// `<key>.json`, the URL, the total length and when it was last read. Only a
/// prefix is kept, never scattered ranges: a person who jumps to the middle
/// is served the middle from the origin, and what is kept stays one
/// contiguous run that is trivially correct to serve. Starting playback,
/// which is what `precache` is for and what people wait on, is always at the
/// front.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'media_cache.dart';

final class DVDiskMediaCache implements DVMediaCache {
  DVDiskMediaCache(this.directory, {this.maxBytes = 512 * 1024 * 1024})
      : _client = HttpClient()..autoUncompress = false;

  /// Owned by the cache: everything in it may be deleted.
  final String directory;

  /// The cache's ceiling. Least recently read entries are deleted past it.
  final int maxBytes;

  final HttpClient _client;
  HttpServer? _server;
  Future<HttpServer>? _starting;
  final Map<String, _Entry> _entries = <String, _Entry>{};
  final Map<String, Future<void>> _precaching = <String, Future<void>>{};
  int _clock = 0;
  bool _closed = false;

  static bool _cacheable(String url) {
    final Uri? uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static String _keyOf(String url) =>
      sha256.convert(utf8.encode(url)).toString();

  int _tick() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    _clock = now > _clock ? now : _clock + 1;
    return _clock;
  }

  Directory _ensureDirectory() {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  _Entry _entry(String url) {
    final String key = _keyOf(url);
    return _entries[key] ??= _Entry.load(directory, key, url);
  }

  @override
  Future<String> playbackAddress(String url) async {
    if (!_cacheable(url)) return url;
    if (_closed) throw StateError('This media cache is closed.');
    _ensureDirectory();
    final _Entry entry = _entry(url);
    entry.lastAccess = _tick();
    entry.saveMeta();
    final HttpServer server = await _listen();
    return 'http://127.0.0.1:${server.port}/${entry.key}';
  }

  Future<HttpServer> _listen() {
    final HttpServer? running = _server;
    if (running != null) return Future<HttpServer>.value(running);
    return _starting ??= () async {
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        unawaited(_serve(request).then((_) {}, onError: (Object _) {}));
      });
      _server = server;
      return server;
    }();
  }

  @override
  Future<bool> contains(String url, {int? bytes}) async {
    if (!_cacheable(url)) return false;
    final _Entry entry = _entry(url);
    final int prefix = entry.prefix;
    if (bytes == null) return entry.complete;
    final int? total = entry.length;
    return prefix >= bytes || (total != null && prefix >= total && prefix > 0);
  }

  @override
  Future<void> precache(String url, {int? bytes}) async {
    if (!_cacheable(url)) return;
    _ensureDirectory();
    // No await between the check and the registration: two calls in the
    // same turn would both see nothing in flight and fetch twice.
    while (_precaching[url] != null) {
      await _precaching[url]!.then((_) {}, onError: (Object _) {});
    }
    final _Entry entry = _entry(url);
    entry.lastAccess = _tick();
    final Future<void> filling = () async {
      if (await contains(url, bytes: bytes)) return;
      await _fill(entry, bytes);
    }();
    _precaching[url] = filling;
    try {
      await filling;
    } finally {
      if (identical(_precaching[url], filling)) _precaching.remove(url)?.ignore();
    }
  }

  Future<void> _fill(_Entry entry, int? bytes) async {
    await entry.waitForWriter();
    final int from = entry.prefix;
    final int? total = entry.length;
    int? to = bytes == null ? null : bytes - 1;
    if (total != null) {
      final int last = total - 1;
      if (to == null || to > last) to = last;
    }
    if (to != null && from > to) return;
    final _Origin origin = await _Origin.open(_client, entry.url, from, to);
    if (origin.status >= 400) {
      await origin.drain();
      throw HttpException('the origin answered ${origin.status}',
          uri: Uri.parse(entry.url));
    }
    entry.length ??= origin.total;
    entry.contentType ??= origin.contentType;
    final _Writer writer = entry.beginWrite();
    try {
      await for (final List<int> chunk in origin.body(from, to)) {
        writer.add(chunk);
      }
    } finally {
      await writer.close();
      entry.saveMeta();
    }
    await _evict();
  }

  Future<void> _serve(HttpRequest request) async {
    final HttpResponse response = request.response;
    final String key =
        request.uri.pathSegments.isEmpty ? '' : request.uri.pathSegments.first;
    final _Entry? entry = _entries[key];
    if (entry == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    entry.readers++;
    entry.lastAccess = _tick();
    try {
      await _answer(request, entry);
    } finally {
      entry.readers--;
      entry.saveMeta();
    }
    await _evict();
  }

  Future<void> _answer(HttpRequest request, _Entry entry) async {
    final HttpResponse response = request.response;
    final bool head = request.method == 'HEAD';
    final (int, int?)? asked =
        _parseRange(request.headers.value(HttpHeaders.rangeHeader), entry.length);
    int start = asked?.$1 ?? 0;
    int? end = asked?.$2;
    final int prefix = entry.prefix;
    int? total = entry.length;

    // Everything asked for is already on disk.
    final bool onDisk = total != null &&
        prefix > 0 &&
        start < prefix &&
        (end ?? total - 1) < prefix;

    _Origin? origin;
    int originFrom = start > prefix ? start : prefix;
    if (!onDisk) {
      if (start > prefix) originFrom = start;
      int? originTo = end;
      if (total != null && originTo == null) originTo = total - 1;
      origin = await _Origin.open(_client, entry.url, originFrom, originTo);
      if (origin.status >= 400) {
        response.statusCode = origin.status;
        await origin.drain();
        await response.close();
        return;
      }
      if (entry.length == null && origin.total != null) {
        entry.length = origin.total;
        entry.saveMeta();
      }
      entry.contentType ??= origin.contentType;
      total = entry.length;
    }

    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final String? type = entry.contentType;
    if (type != null) response.headers.set(HttpHeaders.contentTypeHeader, type);
    if (total != null) {
      if (start >= total) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set('content-range', 'bytes */$total');
        await origin?.drain();
        await response.close();
        return;
      }
      final int last = end == null || end >= total ? total - 1 : end;
      end = last;
      response.contentLength = last - start + 1;
      if (asked != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set('content-range', 'bytes $start-$last/$total');
      }
    } else {
      // The origin gave no length. The body is passed on as it comes.
      start = 0;
      end = null;
    }

    if (head) {
      await origin?.drain();
      await response.close();
      return;
    }

    try {
      // From disk, as far as the disk goes.
      if (prefix > start) {
        final int diskEnd = end == null || end + 1 > prefix ? prefix : end + 1;
        await response.addStream(entry.dataFile.openRead(start, diskEnd));
      }
      final _Origin? live = origin;
      if (live != null) {
        // Kept when it continues exactly where the disk stops and nothing
        // else is writing; passed through otherwise.
        final _Writer? writer =
            originFrom == entry.prefix && !entry.writing ? entry.beginWrite() : null;
        try {
          await for (final List<int> chunk in live.body(originFrom, end)) {
            writer?.add(chunk);
            response.add(chunk);
          }
        } finally {
          await writer?.close();
        }
      }
      await response.close();
    } on Object {
      // The player went away mid-read: a seek, or the page closed. What was
      // written stays, because it is a correct prefix.
      try {
        await response.close();
      } on Object {
        // Already gone.
      }
    }
  }

  /// `bytes=a-b`, `bytes=a-` and `bytes=-n` as an inclusive start and end.
  static (int, int?)? _parseRange(String? header, int? total) {
    if (header == null) return null;
    final RegExpMatch? match =
        RegExp(r'^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)').firstMatch(header);
    if (match == null) return null;
    final String a = match.group(1)!;
    final String b = match.group(2)!;
    if (a.isEmpty) {
      if (b.isEmpty || total == null) return null;
      final int suffix = int.parse(b);
      final int start = total - suffix < 0 ? 0 : total - suffix;
      return (start, total - 1);
    }
    return (int.parse(a), b.isEmpty ? null : int.parse(b));
  }

  Future<void> _evict() async {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) return;
    final List<_Entry> all = <_Entry>[];
    for (final FileSystemEntity file in dir.listSync()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final String name = file.uri.pathSegments.last;
      final String key = name.substring(0, name.length - '.json'.length);
      final _Entry? entry = _entries[key] ?? _Entry.fromDisk(directory, key);
      if (entry != null) all.add(entry);
    }
    int used = 0;
    for (final _Entry entry in all) {
      used += entry.prefix;
    }
    if (used <= maxBytes) return;
    all.sort((_Entry a, _Entry b) => a.lastAccess.compareTo(b.lastAccess));
    for (final _Entry entry in all) {
      if (used <= maxBytes) break;
      if (entry.readers > 0 || entry.writing) continue;
      used -= entry.prefix;
      entry.delete();
      _entries.remove(entry.key);
    }
  }

  @override
  Future<int> size() async {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) return 0;
    int used = 0;
    for (final FileSystemEntity file in dir.listSync()) {
      if (file is File && file.path.endsWith('.data')) used += file.lengthSync();
    }
    return used;
  }

  @override
  Future<void> clear() async {
    final Directory dir = Directory(directory);
    if (!dir.existsSync()) return;
    for (final FileSystemEntity file in dir.listSync()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final String name = file.uri.pathSegments.last;
      final String key = name.substring(0, name.length - '.json'.length);
      final _Entry? entry = _entries[key];
      if (entry != null && (entry.readers > 0 || entry.writing)) continue;
      File('$directory/$key.data').deleteIfPresent();
      file.deleteIfPresent();
      _entries[key]?.forget();
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    final HttpServer? server = _server ?? await _starting;
    _server = null;
    _starting = null;
    await server?.close(force: true);
    _client.close(force: true);
  }
}

extension on File {
  void deleteIfPresent() {
    try {
      deleteSync();
    } on FileSystemException {
      // Already gone.
    }
  }
}

final class _Entry {
  _Entry(this.directory, this.key, this.url,
      {this.length, this.contentType, this.lastAccess = 0});

  factory _Entry.load(String directory, String key, String url) =>
      _Entry.fromDisk(directory, key) ?? _Entry(directory, key, url);

  static _Entry? fromDisk(String directory, String key) {
    final File meta = File('$directory/$key.json');
    if (!meta.existsSync()) return null;
    try {
      final Map<String, Object?> json =
          (jsonDecode(meta.readAsStringSync()) as Map).cast<String, Object?>();
      return _Entry(
        directory,
        key,
        json['url']! as String,
        length: (json['length'] as num?)?.toInt(),
        contentType: json['contentType'] as String?,
        lastAccess: (json['lastAccess'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      return null;
    }
  }

  final String directory;
  final String key;
  final String url;
  int? length;
  String? contentType;
  int lastAccess;
  int readers = 0;
  bool writing = false;
  Completer<void>? _writeDone;

  File get dataFile => File('$directory/$key.data');
  File get _metaFile => File('$directory/$key.json');

  int get prefix {
    final File data = dataFile;
    return data.existsSync() ? data.lengthSync() : 0;
  }

  bool get complete {
    final int? total = length;
    return total != null && total > 0 && prefix >= total;
  }

  void saveMeta() {
    if (!Directory(directory).existsSync()) return;
    _metaFile.writeAsStringSync(jsonEncode(<String, Object?>{
      'url': url,
      'length': length,
      'contentType': contentType,
      'lastAccess': lastAccess,
    }));
  }

  Future<void> waitForWriter() async {
    while (writing) {
      await (_writeDone?.future ?? Future<void>.value());
    }
  }

  _Writer beginWrite() {
    writing = true;
    _writeDone = Completer<void>();
    return _Writer(this, dataFile.openSync(mode: FileMode.append));
  }

  void _endWrite() {
    writing = false;
    final Completer<void>? done = _writeDone;
    _writeDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  void delete() {
    dataFile.deleteIfPresent();
    _metaFile.deleteIfPresent();
    forget();
  }

  void forget() {
    length = null;
    contentType = null;
  }
}

final class _Writer {
  _Writer(this.entry, this.file);

  final _Entry entry;
  final RandomAccessFile file;
  bool _closed = false;

  void add(List<int> bytes) {
    if (!_closed) file.writeFromSync(bytes);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    file.closeSync();
    entry._endWrite();
  }
}

/// One request to the origin, normalised: whether or not the origin honours
/// ranges, [body] yields exactly the bytes from `from` to `to`.
final class _Origin {
  _Origin(this.response, this.status, this.total, this.contentType,
      {required this.startsAt});

  final HttpClientResponse response;
  final int status;
  final int? total;
  final String? contentType;

  /// Where the body the origin sent begins. Zero when it ignored the range.
  final int startsAt;

  static Future<_Origin> open(
      HttpClient client, String url, int from, int? to) async {
    final HttpClientRequest request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (from > 0 || to != null) {
      request.headers
          .set(HttpHeaders.rangeHeader, 'bytes=$from-${to ?? ''}');
    }
    final HttpClientResponse response = await request.close();
    final int status = response.statusCode;
    int? total;
    int startsAt = 0;
    if (status == HttpStatus.partialContent) {
      final RegExpMatch? match = RegExp(r'bytes\s+(\d+)-\d+/(\d+|\*)')
          .firstMatch(response.headers.value('content-range') ?? '');
      if (match != null) {
        startsAt = int.parse(match.group(1)!);
        total = int.tryParse(match.group(2)!);
      } else {
        startsAt = from;
      }
    } else if (status == HttpStatus.ok && response.contentLength >= 0) {
      total = response.contentLength;
    }
    return _Origin(response, status, total,
        response.headers.value(HttpHeaders.contentTypeHeader),
        startsAt: startsAt);
  }

  Stream<List<int>> body(int from, int? to) async* {
    int offset = startsAt;
    final int? last = to;
    await for (final List<int> chunk in response) {
      final int chunkEnd = offset + chunk.length; // exclusive
      int lo = 0;
      int hi = chunk.length;
      if (offset < from) lo = from - offset;
      if (last != null && chunkEnd > last + 1) hi = last + 1 - offset;
      offset = chunkEnd;
      if (lo < hi && lo >= 0) {
        yield lo == 0 && hi == chunk.length ? chunk : chunk.sublist(lo, hi);
      }
      if (last != null && offset > last) break;
    }
  }

  Future<void> drain() async {
    try {
      await response.drain<void>();
    } on Object {
      // Nothing to read.
    }
  }
}
