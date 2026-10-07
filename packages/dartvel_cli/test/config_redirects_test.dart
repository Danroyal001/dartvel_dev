import 'dart:convert';

import 'package:dartvel_cli/src/build/web_server.dart';
import 'package:test/test.dart';

void main() {
  test('dartvel.redirects reaches the manifest, with problems reported and left out', () {
    final List<String> problems = <String>[];
    final Map<String, DVConfiguredRedirectDeclaration> redirects = dvParseRedirects(<String, Object?>{
      '/downloads': '/downloads/',
      '/botm': <String, Object?>{'to': '/book-of-the-month/', 'status': 302},
      'nope': '/x',
      '/loop': '/loop',
      '/bad-status': <String, Object?>{'to': '/x', 'status': 200},
      '/no-target': 42,
    }, problems);
    expect(redirects.keys, <String>['/downloads', '/botm']);
    expect(problems, hasLength(4));
    final Map<String, Object?> manifest = jsonDecode(dvWebServerManifest(
      routes: const <String>['/'],
      titles: const <String, String>{},
      text: const <String, List<String>>{},
      siteUrl: null,
      redirects: redirects,
    )) as Map<String, Object?>;
    expect(manifest['redirects'], <String, Object?>{
      '/downloads': <String, Object?>{'to': '/downloads/', 'status': 301},
      '/botm': <String, Object?>{'to': '/book-of-the-month/', 'status': 302},
    });
  });
}
