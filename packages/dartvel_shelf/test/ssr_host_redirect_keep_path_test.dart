// A duplicate host retired with `keepPath: true` sends every link to the
// same page on the real host, query and all: www.dartvel.dev/docs?x=1 is a
// 301 to https://dartvel.dev/docs?x=1, answered before any routing.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_keep_path_');
    File(p.join(root.path, 'index.html'))
        .writeAsStringSync('<!DOCTYPE html><html><head><title>Site</title></head><body></body></html>');
    File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(<String, Object?>{
      'siteUrl': 'https://dartvel.dev',
      'hostRedirects': <Object?>[
        <String, Object?>{'pattern': 'www.dartvel.dev', 'to': 'https://dartvel.dev', 'keepPath': true},
      ],
      'routes': <String, Object?>{
        '/': <String, Object?>{'title': 'Home'},
        '/docs': <String, Object?>{'title': 'Docs'},
      },
    }));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<Response> get(String host, String path) => handleSsrFallback(
        Request(
          method: 'GET',
          url: Uri.parse('http://$host$path'),
          headers: Headers()..set('host', host),
          bodyStream: const Stream<List<int>>.empty(),
        ),
        root.path,
      );

  test('the path and the query are kept', () async {
    final Response response = await get('www.dartvel.dev', '/docs?x=1');
    expect(response.status, 301);
    expect(response.headers.get('location'), 'https://dartvel.dev/docs?x=1');
    expect((await get('www.dartvel.dev', '/')).headers.get('location'), 'https://dartvel.dev/');
  });

  test('the real host is served as it always was', () async {
    expect((await get('dartvel.dev', '/docs')).status, 200);
  });
}
