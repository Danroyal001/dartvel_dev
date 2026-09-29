/// How long a browser and a shared cache may keep what a server sends.
///
/// Declared under `dartvel.web.server.http` in pubspec.yaml; the build carries
/// it to the server in the manifest, as it does the rest of
/// `dartvel.web.server`. The defaults are the ones that are right with
/// nothing declared, on any host, behind any CDN:
///
/// * a file whose name carries its content hash (`app.3f2a9c1b.js`) is
///   `public, max-age=31536000, immutable`: a new body is a new name;
/// * every other file is `public, no-cache`: kept, and revalidated with its
///   ETag on every use, which costs a 304. Flutter's own output has the same
///   name in every build, so kept for any fixed time a browser would pair a
///   new `main.dart.js` with the previous build's parts;
/// * a document -- a page, an `.html` file -- is `no-cache`;
/// * a protected response (Studio, anything behind a grant) is
///   `private, no-store`, whatever is declared: a shared cache that kept one
///   would hand it to the next person who asked.
library;

/// The directive for a protected response. Not configurable.
const String dvProtectedCacheControl = 'private, no-store';

const String _immutable = 'public, max-age=31536000, immutable';

/// A content hash in a file name: eight or more hex digits, with at least
/// one digit and one letter, set off by `.`, `-` or `_`. Digits alone are a
/// date or a counter as often as a hash.
final RegExp _hashed = RegExp(r'(?:^|[._-])([0-9a-f]{8,})(?=[._-])');

bool _looksHashed(String name) {
  for (final RegExpMatch match in _hashed.allMatches(name)) {
    final String run = match.group(1)!;
    if (run.contains(RegExp('[0-9]')) && run.contains(RegExp('[a-f]'))) return true;
  }
  return false;
}

/// What a server tells caches about what it sends.
final class DVAssetHttpPolicy {
  const DVAssetHttpPolicy({
    this.maxAge,
    this.sMaxAge,
    this.staleWhileRevalidate,
    this.immutable = const <String>[],
    this.documents = 'no-cache',
    this.memoryCacheBytes = 16 * 1024 * 1024,
    this.diskCache = true,
  });

  /// Seconds a browser may keep a file whose name is not hashed without
  /// asking again. Null: it asks every time.
  final int? maxAge;

  /// Seconds a shared cache may keep one. Null: what [maxAge] says.
  final int? sMaxAge;

  /// Seconds a stale one may still be served while it is revalidated.
  final int? staleWhileRevalidate;

  /// Globs of paths that never change under their name (`canvaskit/**`),
  /// beyond the ones whose name is hashed.
  final List<String> immutable;

  /// The directive a document goes out with.
  final String documents;

  /// How much of its site the server keeps in memory. Zero keeps nothing.
  final int memoryCacheBytes;

  /// Whether a file the server has had to decode is kept on disk, beside its
  /// data, for the next client that needs it decoded.
  final bool diskCache;

  /// The `Cache-Control` for the file at [path], which is [protected] when
  /// only an authorised caller may be sent it.
  String cacheControl(String path, {bool protected = false}) {
    if (protected) return dvProtectedCacheControl;
    final String name = path.split('/').last.toLowerCase();
    if (_looksHashed(name) || immutable.any((String glob) => _glob(glob).hasMatch(path))) {
      return _immutable;
    }
    if (name.endsWith('.html') || name.endsWith('.htm')) return documents;
    if (maxAge == null && sMaxAge == null && staleWhileRevalidate == null) {
      return 'public, no-cache';
    }
    return <String>[
      'public',
      'max-age=${maxAge ?? 0}',
      if (sMaxAge != null) 's-maxage=$sMaxAge',
      if (staleWhileRevalidate != null) 'stale-while-revalidate=$staleWhileRevalidate',
    ].join(', ');
  }

  static final Map<String, RegExp> _globs = <String, RegExp>{};

  /// A glob as a pattern: `**` any number of segments, `*` and `?` within
  /// one.
  static RegExp _glob(String glob) => _globs.putIfAbsent(glob, () {
        final StringBuffer out = StringBuffer('^');
        for (int i = 0; i < glob.length; i++) {
          final String c = glob[i];
          if (c == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
            out.write('.*');
            i++;
            if (i + 1 < glob.length && glob[i + 1] == '/') i++;
          } else if (c == '*') {
            out.write('[^/]*');
          } else if (c == '?') {
            out.write('[^/]');
          } else {
            out.write(RegExp.escape(c));
          }
        }
        out.write(r'$');
        return RegExp(out.toString());
      });

  /// `dartvel.web.server.http`. A value of the wrong kind is the default
  /// rather than an error: the manifest is read by a server in production,
  /// where refusing to start over a cache setting is worse than ignoring it.
  static DVAssetHttpPolicy parse(Object? section) {
    final Map<Object?, Object?> m = section is Map ? section : const <Object?, Object?>{};
    int? seconds(Object? v) => v is num && v >= 0 ? v.toInt() : null;
    final Object? immutable = m['immutable'];
    final Object? documents = m['documents'];
    final Object? memory = m['memoryCacheMB'];
    return DVAssetHttpPolicy(
      maxAge: seconds(m['maxAge']),
      sMaxAge: seconds(m['sMaxAge']),
      staleWhileRevalidate: seconds(m['staleWhileRevalidate']),
      immutable: immutable is List
          ? <String>[for (final Object? g in immutable) if (g is String && g.isNotEmpty) g]
          : const <String>[],
      documents: documents is String && documents.trim().isNotEmpty ? documents.trim() : 'no-cache',
      memoryCacheBytes: memory is num && memory >= 0
          ? (memory * 1024 * 1024).round()
          : 16 * 1024 * 1024,
      diskCache: m['diskCache'] is bool ? m['diskCache']! as bool : true,
    );
  }

  /// What was declared, and nothing that was not.
  Map<String, Object?> toJson() => <String, Object?>{
        if (maxAge != null) 'maxAge': maxAge,
        if (sMaxAge != null) 'sMaxAge': sMaxAge,
        if (staleWhileRevalidate != null) 'staleWhileRevalidate': staleWhileRevalidate,
        if (immutable.isNotEmpty) 'immutable': immutable,
        if (documents != 'no-cache') 'documents': documents,
        if (memoryCacheBytes != 16 * 1024 * 1024) 'memoryCacheMB': memoryCacheBytes / (1024 * 1024),
        if (!diskCache) 'diskCache': false,
      };
}
