/// What Studio's media library accepts and how it serves it.
///
/// A media library takes files from one person and hands them to others, so
/// both halves are a security boundary. An SVG, an HTML page or a script
/// served from the application's origin is code running as whoever opens it,
/// and a content type the browser is allowed to guess is the same thing by
/// another route. So the library takes a closed list of types, names the type
/// itself from the file's extension rather than believing the uploader, and
/// serves every file with `nosniff` and a `sandbox` policy.
///
/// That `sandbox` is not a Content-Security-Policy for the application --
/// Dartvel deliberately sets none, since one has to describe an application's
/// own scripts. It is about one uploaded file, which has no scripts that
/// should run: opened directly, it is a document with no origin.
library;

/// Where the library keeps its files in storage. Nothing outside it is
/// reachable through the library, whatever key a request names.
const String dvStudioMediaPrefix = 'media/';

/// The public address of the library: `/_dartvel/media/<name>`.
const String dvStudioPublicMediaPath = '/_dartvel/media/';

/// The largest upload taken by default: 25 MB.
const int dvStudioDefaultMaxMediaBytes = 25 * 1024 * 1024;

/// The types the library takes, by extension. Absent on purpose: SVG, HTML,
/// XHTML, XML, JavaScript and anything else a browser runs.
const Map<String, String> dvStudioMediaTypes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'avif': 'image/avif',
  'ico': 'image/x-icon',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'mov': 'video/quicktime',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'json': 'application/json',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'zip': 'application/zip',
  'woff2': 'font/woff2',
};

/// The type [name] is served as, or null when the library does not take it.
String? dvStudioMediaTypeFor(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return dvStudioMediaTypes[name.substring(dot + 1).toLowerCase()];
}

/// Whether [key] names a file inside the library: under [dvStudioMediaPrefix],
/// with no segment that climbs out of it and nothing a path would read
/// differently on another system.
bool dvStudioIsMediaKey(String key) {
  if (!key.startsWith(dvStudioMediaPrefix)) return false;
  if (key.contains('\\') || key.contains('\u0000')) return false;
  final List<String> segments =
      key.substring(dvStudioMediaPrefix.length).split('/');
  return segments.isNotEmpty &&
      segments.every((String s) => s.isNotEmpty && s != '.' && s != '..');
}

/// The public address of the file at [key].
String dvStudioMediaPublicUrl(String key) =>
    '$dvStudioPublicMediaPath'
    '${key.substring(dvStudioMediaPrefix.length).split('/').map(Uri.encodeComponent).join('/')}';

/// The headers a library file is served with. [public] for the visitors'
/// address, where a file never changes under its key and may be cached for a
/// year; otherwise it is behind the Studio grant and only the browser that
/// asked keeps it.
Map<String, String> dvStudioMediaHeaders(String type, {required bool public}) {
  // Pictures, video, sound and PDFs are shown in place; anything else is
  // downloaded rather than opened as a page.
  final bool inline = type.startsWith('image/') ||
      type.startsWith('video/') ||
      type.startsWith('audio/') ||
      type == 'application/pdf';
  return <String, String>{
    'content-type': type,
    'x-content-type-options': 'nosniff',
    'content-security-policy': "sandbox; default-src 'none'; "
        "img-src 'self'; media-src 'self'; style-src 'unsafe-inline'",
    'content-disposition': inline ? 'inline' : 'attachment',
    'cache-control': public
        ? 'public, max-age=31536000, immutable'
        : 'private, max-age=3600',
  };
}
