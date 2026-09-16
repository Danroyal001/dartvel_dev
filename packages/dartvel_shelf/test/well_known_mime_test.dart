// The deep-link verification documents are JSON whatever their names say.
//
// `apple-app-site-association` has no extension, so a server that picks a
// content type from the extension served it as application/octet-stream --
// and iOS refuses a document not served as JSON (DV-LINKS-002), so every
// Universal Link opened Safari from a site that looked right.
import 'package:dartvel_shelf/src/server.dart' show getMimeType;
import 'package:test/test.dart';

void main() {
  test('apple-app-site-association is served as JSON', () {
    expect(
      getMimeType('/srv/web/.well-known/apple-app-site-association'),
      'application/json',
    );
  });

  test('assetlinks.json already was', () {
    expect(
      getMimeType('/srv/web/.well-known/assetlinks.json'),
      'application/json',
    );
  });

  test('a file with no extension elsewhere is still bytes', () {
    expect(getMimeType('/srv/web/LICENSE'), 'application/octet-stream');
  });
}
