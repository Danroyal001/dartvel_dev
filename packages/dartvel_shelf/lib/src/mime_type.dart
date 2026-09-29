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
    default:
      return 'application/octet-stream';
  }
}
