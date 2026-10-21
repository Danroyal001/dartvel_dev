/// The iOS drag and drop bridge's JSON, as the map [DVDropEvent.fromMap]
/// takes. Pure Dart, so the translation is tested on the VM.
library;

/// A drop from the generated `DartvelDragDrop` Swift bridge. Each item is a
/// file the bridge has already copied into the application's temporary
/// directory (`path`, `name`, `mimeType`), a `url`, or `text`. UIKit reports
/// the position in points, which are Flutter's logical pixels already.
///
/// The copy is not optional: `NSItemProvider` hands a file over in a
/// callback whose file is deleted when the callback returns.
Map<String, Object?> dvIosDropMap(Map<Object?, Object?> raw) {
  final List<Map<String, Object?>> files = <Map<String, Object?>>[];
  final List<String> urls = <String>[];
  final List<String> texts = <String>[];
  for (final Object? item in (raw['items'] as List?) ?? const <Object?>[]) {
    if (item is! Map) continue;
    final String? path = item['path'] as String?;
    final String? url = item['url'] as String?;
    final String? text = item['text'] as String?;
    if (path != null) {
      files.add(<String, Object?>{
        'path': path,
        if (item['name'] != null) 'name': item['name'],
        if (item['mimeType'] != null) 'mimeType': item['mimeType'],
        if (item['size'] != null) 'size': item['size'],
      });
    } else if (url != null) {
      final Uri? parsed = Uri.tryParse(url);
      if (parsed != null && parsed.scheme == 'file') {
        files.add(<String, Object?>{'path': parsed.toFilePath()});
      } else {
        urls.add(url);
      }
    } else if (text != null && text.isNotEmpty) {
      texts.add(text);
    }
  }
  return <String, Object?>{
    'files': files,
    'urls': urls,
    if (texts.isNotEmpty) 'text': texts.join('\n'),
    'x': raw['x'] ?? 0,
    'y': raw['y'] ?? 0,
  };
}
