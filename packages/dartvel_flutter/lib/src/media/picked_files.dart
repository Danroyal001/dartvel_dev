/// Photos and files a person picks from the device, as the `DVFile` a capture
/// gives.
///
/// The picker binding (`media.pick`) answers with a path on a device and with
/// the bytes in a browser, which has no path to give. A browser's pick is put
/// in the page's capture store and named by a key, which is exactly what a
/// camera's photo is, so `DV.Platform.media.readCapture` opens either.
library;

import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';

import 'web_media_mapping.dart' show DVWebCaptureStore;

/// This target has no picker for photos or files.
final class DVPickUnsupported implements Exception {
  const DVPickUnsupported(this.reason);

  /// What to tell the person or the developer.
  final String reason;

  @override
  String toString() => 'DVPickUnsupported: $reason';
}

/// What [DV.Platform.media.pickFiles] asks the picker for. [types] are kinds
/// (`image`, `video`, `audio`), media types (`application/pdf`) or extensions
/// (`.csv` or `csv`).
Map<String, Object?> dvPickArguments({
  required String type,
  required List<String> types,
  required bool multiple,
}) {
  final List<String> accept = <String>[
    for (final String entry in types)
      if (entry.trim().isNotEmpty) _acceptEntry(entry.trim()),
  ];
  return <String, Object?>{
    'type': type,
    'multiple': multiple,
    if (accept.isNotEmpty) 'accept': accept,
  };
}

String _acceptEntry(String entry) {
  if (entry == 'image' || entry == 'video' || entry == 'audio') return '$entry/*';
  if (entry.contains('/')) return entry;
  return entry.startsWith('.') ? entry : '.$entry';
}

/// The files in [answer], which is what `media.pick` returned.
Future<List<DVFile>> dvPickedFiles(Object? answer, {DVWebCaptureStore? store}) async {
  final DVWebCaptureStore bytesStore = store ?? DVWebCaptureStore.instance;
  final List<DVFile> files = <DVFile>[];
  for (final Object? item in answer is List ? answer : const <Object?>[]) {
    if (item is! Map) continue;
    final Object? path = item['path'];
    final Object? bytes = item['bytes'];
    final String name = '${item['name'] ?? (path is String ? path.split(RegExp(r'[\\/]')).last : '')}';
    final String mimeType = _mimeOf(item['mimeType'], name);
    if (path is String && path.isNotEmpty) {
      files.add(DVFile(
        path: path,
        mimeType: mimeType,
        sizeBytes: (item['size'] as num?)?.toInt(),
      ));
    } else if (bytes is List<int>) {
      final Uint8List data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final String extension = name.contains('.') ? name.split('.').last : 'bin';
      final String key = await bytesStore.reserve(extension);
      bytesStore.write(key, data);
      files.add(DVFile(path: key, mimeType: mimeType, sizeBytes: data.length));
    }
  }
  return files;
}

String _mimeOf(Object? declared, String name) {
  if (declared is String && declared.isNotEmpty) return declared;
  final String extension =
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return _byExtension[extension] ?? 'application/octet-stream';
}

const Map<String, String> _byExtension = <String, String>{
  'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
  'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
  'svg': 'image/svg+xml', 'heic': 'image/heic', 'avif': 'image/avif',
  'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime',
  'mkv': 'video/x-matroska',
  'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg',
  'm4a': 'audio/mp4', 'flac': 'audio/flac',
  'pdf': 'application/pdf', 'csv': 'text/csv', 'txt': 'text/plain',
  'json': 'application/json', 'zip': 'application/zip',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};
