// A guarded route asked for by somebody signed out.
//
// The web-server build captures every route's page and the server renders it
// on request. For a guarded route that capture is the screen the guard
// protects, and the gate that sends a signed-out reader to sign in runs in
// the client -- after the server had already sent the page. So the server
// asks first: no session, and the answer is the sign-in page.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/http.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n'
    '<!-- dartvel:seo -->\n<title>Shell</title>\n<!-- /dartvel:seo -->\n'
    '</head>\n<body><div id="dartvel-splash"></div></body>\n</html>\n';

Directory site({String? signIn}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_guarded_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'index.html')).writeAsStringSync(shell);
  File(p.join(root.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(
    <String, Object?>{
      if (signIn != null) 'signIn': signIn,
      'redirects': <String, Object?>{
        '/downloads': <String, Object?>{'to': '/downloads/', 'status': 301},
        '/old': <String, Object?>{'to': 'https://example.org/new', 'status': 308},
      },
      'routes': <String, Object?>{
        '/': <String, Object?>{
          'title': 'Today',
          'text': <String>['1450 kcal eaten today'],
          'guarded': true,
        },
        '/about': <String, Object?>{
          'title': 'About',
          'text': <String>['Who we are'],
        },
        '/login': <String, Object?>{'title': 'Sign in', 'text': <String>['Sign in']},
      },
    },
  ));
  return root;
}

Future<Response> get(Directory root, String path) => handleSsrFallback(
      Request(
        method: 'GET',
        url: Uri.parse('http://example.com$path'),
        headers: Headers(),
        bodyStream: const Stream<List<int>>.empty(),
      ),
      root.path,
    );

Future<String> body(Response response) async =>
    utf8.decode(await response.body!.stream.expand((List<int> c) => c).toList());

void main() {
  test('signed out, a guarded route sends the reader to sign in, with where they were going',
      () async {
    final Response response = await get(site(signIn: '/login'), '/?tab=meals');
    expect(response.status, 302);
    expect(response.headers.get('location'), '/login?from=%2F%3Ftab%3Dmeals');
  });

  test('with no sign-in page the guarded route is the bare shell and a 401, never its text',
      () async {
    final Response response = await get(site(), '/');
    expect(response.status, 401);
    expect(await body(response), isNot(contains('1450 kcal')));
  });

  test('an unguarded route and the sign-in page itself are served as before', () async {
    final Directory root = site(signIn: '/login');
    final Response about = await get(root, '/about');
    expect(about.status, 200);
    expect(await body(about), contains('Who we are'));
    expect((await get(root, '/login')).status, 200);
  });

  test('a declared redirect is answered before the guard and the not-found page', () async {
    final Directory root = site(signIn: '/login');
    final Response downloads = await get(root, '/downloads');
    expect(downloads.status, 301);
    expect(downloads.headers.get('location'), '/downloads/');
    final Response old = await get(root, '/old?x=1');
    expect(old.status, 308);
    expect(old.headers.get('location'), 'https://example.org/new?x=1');
  });

  test('the target of a redirect is not redirected again', () async {
    final Response target = await get(site(signIn: '/login'), '/downloads/');
    expect(target.status, isNot(301));
  });
}
