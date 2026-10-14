// The addresses people try for the docs arrive at a page.
//
// /docs/platform was a page that said "This page moved", listed in the
// sitemap with a canonical to itself, so search engines kept it as a page.
// /docs/getting-started and /docs/install* are where a reader coming from
// another framework's docs looks first, and they answered 404. Each is a
// redirect in dartvel.redirects now, to a page that exists.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final YamlMap dartvel =
      (loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap)['dartvel']
          as YamlMap;
  final Map<String, String> redirects = <String, String>{
    for (final MapEntry<dynamic, dynamic> e
        in ((dartvel['redirects'] as YamlMap?) ?? YamlMap()).entries)
      '${e.key}': e.value is String ? e.value as String : '${(e.value as YamlMap)['to']}',
  };

  /// The page file a route is served from: /docs/native-access is
  /// lib/pages/docs/native-access.dart, /docs is lib/pages/docs/index.dart.
  bool isPage(String route) {
    final String path = route == '/' ? '/index' : route;
    return File('lib/pages$path.dart').existsSync() ||
        File('lib/pages$path/index.dart').existsSync();
  }

  test('the moved docs page is a redirect, not a page', () {
    expect(redirects['/docs/platform'], '/docs/native-access');
    expect(File('lib/pages/docs/platform.dart').existsSync(), isFalse);
  });

  test('the docs addresses people guess are redirected', () {
    for (final String guess in <String>[
      '/docs/getting-started',
      '/docs/install',
      '/docs/installation',
    ]) {
      expect(redirects[guess], '/docs', reason: guess);
    }
  });

  test('every redirect on this site lands on a page that exists', () {
    final List<String> dead = <String>[
      for (final MapEntry<String, String> r in redirects.entries)
        if (r.value.startsWith('/') && !isPage(r.value)) '${r.key} -> ${r.value}',
    ];
    expect(dead, isEmpty, reason: dead.join('\n'));
  });
}
