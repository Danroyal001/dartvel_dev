/// Framework-only rendered documents. No application cache API is added.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

int _generation = 0;

/// Shared by OTA and Studio. Lazy generation invalidation avoids retaining
/// handler instances and discards fills started before the content changed.
void dvPurgeRenderedPages() => _generation++;

int get dvRenderedPagesGeneration => _generation;

final class DVRenderedPage {
  DVRenderedPage(List<int> bytes, Map<String, String> headers)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView(),
      headers = Map.unmodifiable(headers);

  final Uint8List bytes;
  final Map<String, String> headers;
}

final class DVRenderedPageCache {
  DVRenderedPageCache({
    this.maxBytes = 32 * 1024 * 1024,
    this.maxEntries = 256,
  });

  final int maxBytes;
  final int maxEntries;
  final LinkedHashMap<String, DVRenderedPage> _pages = .new();
  int _bytes = 0;
  int _seen = _generation;

  void _refresh() {
    if (_seen == _generation) return;
    _pages.clear();
    _bytes = 0;
    _seen = _generation;
  }

  DVRenderedPage? get(String key) {
    _refresh();
    final page = _pages.remove(key);
    if (page != null) _pages[key] = page;
    return page;
  }

  void put(
    String key,
    List<int> bytes,
    Map<String, String> headers, {
    required int status,
    int? generation,
  }) {
    _refresh();
    if (generation != null && generation != _generation) return;
    if (status != 200 ||
        headers.keys.any((k) => k.toLowerCase() == 'set-cookie') ||
        bytes.length > maxBytes ||
        maxEntries <= 0) {
      return;
    }
    final previous = _pages.remove(key);
    if (previous != null) _bytes -= previous.bytes.length;
    while (_pages.isNotEmpty &&
        (_bytes + bytes.length > maxBytes || _pages.length >= maxEntries)) {
      _bytes -= _pages.remove(_pages.keys.first)!.bytes.length;
    }
    _pages[key] = DVRenderedPage(bytes, headers);
    _bytes += bytes.length;
  }
}

/// Only compiled manifest content may be shared; callers additionally prove
/// that no data resolver runs. Even an anonymous request carrying a cookie is
/// bypassed, including when a previously cached document exists.
bool dvMayCacheRenderedPage(
  String method,
  Map<String, String> headers,
  Map? route, {
  required bool staticContent,
}) =>
    method == 'GET' &&
    staticContent &&
    route != null &&
    route['guarded'] != true &&
    route['cache'] != false &&
    route['location'] == null &&
    !headers.keys.any(
      (k) => const {
        'cookie',
        'authorization',
        'proxy-authorization',
      }.contains(k.toLowerCase()),
    );

/// Every request input is included conservatively. Conditional validators
/// don't change the document and must not create a separate entry.
String dvRenderedPageKey(String site, Uri uri, Map<String, String> headers) {
  final variants = <String, String>{
    for (final e in headers.entries)
      if (!const {
        'if-none-match',
        'if-modified-since',
      }.contains(e.key.toLowerCase()))
        e.key.toLowerCase(): e.value,
  };
  final keys = variants.keys.toList()..sort();
  return jsonEncode([
    site,
    uri.toString(),
    for (final k in keys) [k, variants[k]],
  ]);
}

Map<String, String> dvRenderedPageHeaders(List<int> bytes) => {
  'content-type': 'text/html; charset=utf-8',
  'etag': 'W/"${sha256.convert(bytes)}"',
  // Revalidate so an internal purge takes effect in browsers and CDNs too.
  'cache-control': 'public, no-cache, must-revalidate',
  'vary': 'Cookie, Authorization, Proxy-Authorization, Accept-Encoding, Accept-Language, X-Dartvel-Theme, X-Dartvel-Locale, Sec-GPC',
};

bool dvRenderedPageNotModified(String? condition, String etag) =>
    condition != null &&
    condition.split(',').any((value) {
      final tag = value.trim();
      String opaque(String value) =>
          value.startsWith('W/') ? value.substring(2) : value;
      return tag == '*' || opaque(tag) == opaque(etag);
    });
