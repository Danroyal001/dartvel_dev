// Text that changes by request inside a page the build captured.
//
// The web-server binary serves each route from what `dartvel build` captured,
// so anything that depends on when the page is asked for -- "today's menu",
// a date, an opening-hours line -- was frozen at the moment of the build.
// EatingToday's sign-in page said "MONDAY 16 NOVEMBER" for as long as that
// build was live, whatever the day. A widget marks such text with
// `DVModifier.pageSlot(name)`; the capture keeps the mark; a route's page data
// answers `DVPageData.slots({...})` and the server writes the request's text
// into the captured page, keeping everything else the capture holds.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset="UTF-8">\n'
    '    <title>Site</title>\n  </head>\n  <body>\n    <script src="main.dart.js"></script>\n'
    '  </body>\n</html>\n';

const String _captured = '<h1>Sign in to your kitchen</h1>'
    '<p><span data-dv-slot="menu-date">TODAY\'S MENU · MONDAY 16 NOVEMBER</span></p>'
    '<p><label for="dv-field-1">Email</label> <input id="dv-field-1" type="text" name="Email"></p>'
    '<p><span data-dv-slot="menu-breakfast">Akara</span></p>';

const DVRoutePage _login = DVRoutePage(
  route: '/login',
  title: 'Sign in — EatingToday',
  description: 'Sign in.',
  siteUrl: 'https://example.com',
  siteName: 'EatingToday',
  html: _captured,
);

void main() {
  test('slots replace the marked text and keep the rest of the captured page', () {
    final String html = dvRenderPage(
      shell: _shell,
      path: '/login',
      data: const DVPageData.slots(<String, String>{
        'menu-date': "TODAY'S MENU · TUESDAY 17 NOVEMBER",
        'menu-breakfast': 'Moi Moi',
      }),
      route: _login,
    );
    expect(html, contains('TUESDAY 17 NOVEMBER'));
    expect(html, isNot(contains('MONDAY 16 NOVEMBER')));
    expect(html, contains('Moi Moi'));
    expect(html, isNot(contains('Akara')));
    // The form the capture holds is still there: a slot never costs the page.
    expect(html, contains('name="Email"'));
    expect(html, contains('Sign in to your kitchen'));
    // And the head is the route's own, not an empty title from the slots.
    expect(html, contains('<title>Sign in — EatingToday</title>'));
  });

  test('a slot the data does not name keeps its captured text', () {
    final String html = dvRenderPage(
      shell: _shell,
      path: '/login',
      data: const DVPageData.slots(<String, String>{'menu-date': 'TUESDAY'}),
      route: _login,
    );
    expect(html, contains('Akara'));
  });

  test('a slot value is escaped like every other request value', () {
    final String html = dvRenderPage(
      shell: _shell,
      path: '/login',
      data: const DVPageData.slots(<String, String>{'menu-date': '<script>alert(1)</script>'}),
      route: _login,
    );
    expect(html, isNot(contains('<script>alert(1)')));
    expect(html, contains('&lt;script&gt;'));
  });

  test('dvFillPageSlots fills by name only', () {
    expect(
      dvFillPageSlots('<p><span data-dv-slot="a">x</span><span data-dv-slot="ab">y</span></p>', <String, String>{'a': 'X'}),
      '<p><span data-dv-slot="a">X</span><span data-dv-slot="ab">y</span></p>',
    );
  });

  test('slots survive a shared page cache', () {
    const DVPageData data = DVPageData.slots(<String, String>{'menu-date': 'TUESDAY'});
    final DVPageData back = DVPageData.fromJson(data.toJson());
    expect(back.slots, <String, String>{'menu-date': 'TUESDAY'});
    expect(back.title, '');
  });
}
