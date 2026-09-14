/// A file the application holds: what capture returns, and what Media
/// Pipeline's upload validation takes.
library;

/// A file on this device, with what is known about it.
///
/// Deliberately small. It names bytes that already exist somewhere private to
/// the application; reading them, uploading them and generating variants of
/// them are other APIs' work.
final class DVFile {
  const DVFile({
    required this.path,
    required this.mimeType,
    this.sizeBytes,
    this.duration,
  });

  /// Absolute path on this device.
  final String path;

  /// The media type the producer wrote, e.g. `audio/ogg`. A claim, not a
  /// verification: upload validation decodes before it trusts it.
  final String mimeType;

  /// Size on disk when this was produced, when known.
  final int? sizeBytes;

  /// Media duration, for audio and video.
  final Duration? duration;

  @override
  String toString() => 'DVFile($path, $mimeType)';
}
