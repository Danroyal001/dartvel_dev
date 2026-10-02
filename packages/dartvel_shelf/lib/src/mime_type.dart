/// The content type a site file is served with, by its name.
library;

import 'package:path/path.dart' as p;

String getMimeType(String path) {
  // iOS refuses the Universal Links document as anything but JSON, and its
  // name has no extension to say so.
  if (p.basename(path) == 'apple-app-site-association') {
    return 'application/json';
  }
  final ext = p.extension(path).toLowerCase();
  switch (ext) {
    case '.html':
      return 'text/html';
    case '.css':
      return 'text/css';
    case '.js':
      return 'application/javascript';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.svg':
      return 'image/svg+xml';
    case '.json':
      return 'application/json';
    case '.wasm':
      return 'application/wasm';
    // Text a crawler or a person reads. Served as octet-stream, a sitemap is
    // a download rather than a document, and a search console reports it as
    // unreadable.
    case '.xml':
    case '.xsl':
      return 'application/xml; charset=utf-8';
    case '.txt':
      return 'text/plain; charset=utf-8';
    case '.csv':
      return 'text/csv; charset=utf-8';
    case '.md':
      return 'text/markdown; charset=utf-8';
    case '.mjs':
      return 'application/javascript';
    case '.map':
      return 'application/json';
    case '.webmanifest':
      return 'application/manifest+json';
    case '.ico':
      return 'image/x-icon';
    case '.webp':
      return 'image/webp';
    case '.avif':
      return 'image/avif';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    case '.ttf':
      return 'font/ttf';
    case '.otf':
      return 'font/otf';
    case '.pdf':
      return 'application/pdf';
    case '.mp4':
      return 'video/mp4';
    case '.webm':
      return 'video/webm';
    case '.mp3':
      return 'audio/mpeg';
    default:
      return 'application/octet-stream';
  }
}
