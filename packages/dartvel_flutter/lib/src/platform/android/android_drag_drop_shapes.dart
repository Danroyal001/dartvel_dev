/// The Android drag and drop bridge's JSON, as the map [DVDropEvent.fromMap]
/// takes. Pure Dart, so the translation is tested on the VM.
library;

/// A drop from `DartvelDragDrop`: each ClipData item is a `uri` (with the
/// provider's `name`, `mimeType` and `size` for a `content://` one) or
/// `text`, and the position is in physical pixels from Flutter's view.
///
/// A `content:` or `file:` URI is a file. Any other URI is a link, and so is
/// an item whose whole text is one web URL, which is how a link dragged out
/// of Chrome arrives. The remaining text items are joined by newlines.
Map<String, Object?> dvAndroidDropMap(
  Map<Object?, Object?> raw, {
  required double devicePixelRatio,
}) {
  final List<Map<String, Object?>> files = <Map<String, Object?>>[];
  final List<String> urls = <String>[];
  final List<String> texts = <String>[];
  for (final Object? item in (raw['items'] as List?) ?? const <Object?>[]) {
    if (item is! Map) continue;
    final String? uri = item['uri'] as String?;
    final String? text = item['text'] as String?;
    if (uri != null) {
      final Uri? parsed = Uri.tryParse(uri);
      if (parsed != null && (parsed.scheme == 'content' || parsed.scheme == 'file')) {
        files.add(<String, Object?>{
          'uri': uri,
          'name': item['name'] ??
              (parsed.pathSegments.isEmpty ? 'file' : parsed.pathSegments.last),
          if (item['mimeType'] != null) 'mimeType': item['mimeType'],
          if (item['size'] != null) 'size': item['size'],
        });
      } else {
        urls.add(uri);
      }
    } else if (text != null && text.isNotEmpty) {
      if (dvIsSingleWebUrl(text)) {
        urls.add(text.trim());
      } else {
        texts.add(text);
      }
    }
  }
  final double ratio = devicePixelRatio > 0 ? devicePixelRatio : 1;
  return <String, Object?>{
    'files': files,
    'urls': urls,
    if (texts.isNotEmpty) 'text': texts.join('\n'),
    'x': ((raw['x'] as num?) ?? 0) / ratio,
    'y': ((raw['y'] as num?) ?? 0) / ratio,
  };
}

/// Whether [text] is nothing but one http(s) URL.
bool dvIsSingleWebUrl(String text) {
  final String trimmed = text.trim();
  if (trimmed.contains(RegExp(r'\s'))) return false;
  final Uri? parsed = Uri.tryParse(trimmed);
  return parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.host.isNotEmpty;
}
