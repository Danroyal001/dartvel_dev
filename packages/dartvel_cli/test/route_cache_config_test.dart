import 'dart:io';
import 'dart:convert';

import 'package:dartvel_cli/src/generators/config_routes.dart';
import 'package:dartvel_cli/src/build/web_server.dart';

import 'package:test/test.dart';

void main() {
  test('route cache false reaches the server manifest', () {
    final root = Directory.systemTemp.createTempSync('route-cache-');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/lib').createSync();
    File('${root.path}/lib/routes.dart').writeAsStringSync('''
final routes = [DVRoute(path: '/clock', cache: false, builder: (c, s) => Clock())];
''');
    final config = DVConfigRoutes.read(root: root.path);
    expect(config.errors, isEmpty);
    expect(config.routes.single.cache, isFalse);
    final manifest = jsonDecode(
      dvWebServerManifest(
        routes: ['/clock'],
        titles: {},
        text: {},
        siteUrl: null,
        uncached: {
          for (final route in config.routes)
            if (!route.cache) route.path,
        },
      ),
    );
    expect(manifest['routes']['/clock']['cache'], false);
  });
}
