/// A file that arrived from outside the application: dropped onto it, or
/// handed to it by the operating system.
///
/// The same type on every target, so a handler written once takes a file a
/// person dropped from a file manager on Linux, a photo dragged in from
/// another app in split screen on Android, a document dropped from Files on
/// an iPad, and a file dropped onto a browser tab. Where the platform names a
/// path it is here; where it hands over a content URI or browser file object
/// instead, [readBytes] still reads it.
library;

import 'dart:typed_data';

import 'incoming_file_io.dart'
    if (dart.library.js_interop) 'incoming_file_web.dart' as local;

/// One file the application was given.
class DVIncomingFile {
  const DVIncomingFile({
    required this.name,
    this.mimeType,
    this.path,
    this.uri,
    this.size,
    Future<Uint8List> Function()? read,
  }) : _read = read;

  /// A file on this machine's filesystem, as a file manager drop names it.
  factory DVIncomingFile.atPath(String path, {String? mimeType}) {
    final List<String> parts = path.split(RegExp(r'[\\/]'));
    return DVIncomingFile(
      name: parts.isEmpty ? path : parts.last,
      path: path,
      mimeType: mimeType ?? dvMimeTypeFor(path),
    );
  }

  /// The file's name, without a directory.
  final String name;

  /// Its type when the platform said, else one guessed from the extension.
  final String? mimeType;

  /// A filesystem path, where the platform gave one (desktop, iOS copies).
  final String? path;

  /// A `content://` URI on Android, or a link the drop carried instead.
  final Uri? uri;

  /// Its size in bytes, when known before reading.
  final int? size;

  final Future<Uint8List> Function()? _read;

  /// The file's contents.
  ///
  /// Read when asked, not when dropped: a drop of a large video should not
  /// stall the drop itself, and most handlers only want the name.
  Future<Uint8List> readBytes() {
    final Future<Uint8List> Function()? read = _read;
    if (read != null) return read();
    final String? filePath = path;
    if (filePath != null) return local.dvReadLocalFile(filePath);
    throw StateError('The platform gave no way to read "$name".');
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        if (mimeType != null) 'mimeType': mimeType,
        if (path != null) 'path': path,
        if (uri != null) 'uri': uri.toString(),
        if (size != null) 'size': size,
      };

  @override
  String toString() => 'DVIncomingFile($name, ${mimeType ?? 'unknown type'})';
}

/// A MIME type for [name] from its extension, or null when it has none this
/// knows. Only a fallback: a platform that reports the type wins.
String? dvMimeTypeFor(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return _byExtension[name.substring(dot + 1).toLowerCase()];
}

const Map<String, String> _byExtension = <String, String>{
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'html': 'text/html',
  'htm': 'text/html',
  'json': 'application/json',
  'xml': 'application/xml',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'svg': 'image/svg+xml',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};
