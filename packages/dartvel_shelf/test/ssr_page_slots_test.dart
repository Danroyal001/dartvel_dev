// The web-server binary writes request-time text into the captured page.
//
// EatingToday's sign-in page showed the menu of the day its build ran, for as
// long as that build was live: the binary serves each route from what the
// build captured. A route's page data can answer DVPageData.slots, and the
// served page is the captured one -- form and all -- with the request's text
// where the app marked it.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_shelf/src/ssr_helper.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset="UTF-8">\n'
    '    <title>Site</title>\n  </head>\n  <body>\n    <script src="main.dart.js"></script>\n'
    '  </body>\n</html>\n';

const DVRoutePage _login = DVRoutePage(
  route: '/login',
  title: 'Sign in — Kitchen',
  siteUrl: 'https://example.com',
  siteName: 'Kitchen',
  html: '<h1>Sign in</h1>'
      '<p><span data-dv-slot="menu-date">MONDAY 16 NOVEMBER</span></p>'
      '<p><label for="dv-field-1">Email</label> <input id="dv-field-1" type="text" name="Email"></p>',
);

void main() {
  late Directory site;

  setUp(() {
    site = Directory.systemTemp.createTempSync('dv_page_slots_');
    File(p.join(site.path, 'index.html')).writeAsStringSync(dvMinifyHtml(_shell));
    File(p.join(site.path, 'dartvel_routes.json')).writeAsStringSync(jsonEncode(<String, Object?>{
      'siteUrl': 'https://example.com',
      'server': <String, Object?>{'pageDataMode': 'await'},
      'routes': <String, Object?>{
        '/login': <String, Object?>{'title': _login.title, 'page': _login.toJson()},
      },
    }));
  });

  tearDown(() => site.deleteSync(recursive: true));

  test('each request gets its own text; the rest is the capture', () async {
    String day = 'TUESDAY 17 NOVEMBER';
    final DVPageDataResolver pageData = dvRoutePageResolver(<String, DVPageDataResolver>{
      '/login': (DVPageRequest request) => DVPageData.slots(<String, String>{'menu-date': day}),
    });
    Future<String> get() async {
      final Response response = await handleSsrFallback(
        Request(
          method: 'GET',
          url: Uri.parse('http://localhost/login'),
          headers: Headers(const <String, String>{}),
          bodyStream: const Stream<List<int>>.empty(),
        ),
        site.path,
        pageData: pageData,
      );
      return utf8.decode(await response.body!.bytes());
    }

    final String tuesday = await get();
    expect(tuesday, contains('TUESDAY 17 NOVEMBER'));
    expect(tuesday, isNot(contains('MONDAY 16 NOVEMBER')));
    expect(tuesday, contains('name="Email"'));
    expect(tuesday, contains('<title>Sign in — Kitchen</title>'));

    day = 'WEDNESDAY 18 NOVEMBER';
    expect(await get(), contains('WEDNESDAY 18 NOVEMBER'));
  });
}
