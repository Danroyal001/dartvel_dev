// `dartvel.images` travels from the build to the web server that resizes.
//
// The server has no pubspec to read: which widths it may resize to and which
// hosts it may fetch from reach it only through dartvel_routes.json. A value
// dropped anywhere on the way is a server refusing every variant the
// application asks for -- or, worse, one that fetches from hosts nobody
// allowed -- so this checks the whole trip, written by the build and read by
// the server's own reader.
import 'dart:io';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:dartvel_core/dartvel.dart' show DVImageVariants;
import 'package:dartvel_shelf/src/image_endpoint.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String manifest({DVImageVariants? images}) => dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{},
      text: const <String, List<String>>{},
      siteUrl: null,
      images: images,
    );

void main() {
  late Directory web;

  setUp(() {
    web = Directory.systemTemp.createTempSync('dv_img_manifest_');
    addTearDown(() => web.deleteSync(recursive: true));
  });

  test('what the build declared is what the server reads', () {
    File(p.join(web.path, 'dartvel_routes.json')).writeAsStringSync(manifest(
      images: const DVImageVariants(
        widths: <int>[320, 640],
        quality: 60,
        remoteHosts: <String>['cdn.example.com'],
        endpoint: true,
      ),
    ));

    final DVImageVariants read = dvImageVariantsFor(web.path);

    expect(read.endpoint, isTrue);
    expect(read.widths, <int>[320, 640]);
    expect(read.quality, 60);
    expect(read.allowsHost('cdn.example.com'), isTrue);
    expect(read.allowsHost('elsewhere.example.org'), isFalse);
  });

  test('a build with no variants gives the server none to answer', () {
    // Absent, not an empty declaration: the endpoint then answers that
    // address like any other and resizes nothing.
    final String written = manifest(images: const DVImageVariants());
    expect(written, isNot(contains('"images"')));

    File(p.join(web.path, 'dartvel_routes.json')).writeAsStringSync(written);
    expect(dvImageVariantsFor(web.path).endpoint, isFalse);
  });
}
