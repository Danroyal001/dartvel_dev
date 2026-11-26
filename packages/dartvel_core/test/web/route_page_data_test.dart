import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart' show dvPageResolverIsStatic;
import 'package:test/test.dart';

const _shell = '<!DOCTYPE html><html><head><title>App</title></head><body><div id="app"></div></body></html>';

DVPageRequest _request(String pattern, String path, [Map<String, String> params = const <String, String>{}]) =>
    DVPageRequest(path: path, pattern: pattern, params: params);

void main() {
  group('dvRoutePageResolver', () {
    test("an application's own resolver answers its route, with the path's parameters", () async {
      final resolver = dvRoutePageResolver(<String, DVPageDataResolver>{
        '/days/:day': (request) => DVPageData(title: 'Day ${request.params['day']}'),
      });
      final data = await resolver(_request('/days/:day', '/days/2026-10-20', <String, String>{'day': '2026-10-20'}));
      expect(data?.title, 'Day 2026-10-20');
    });

    test('a route it does not name goes to the fallback, so model pages keep working', () async {
      final resolver = dvRoutePageResolver(
        <String, DVPageDataResolver>{'/days/:day': (_) => const DVPageData(title: 'Day')},
        fallback: (request) => DVPageData(title: 'Model ${request.path}'),
      );
      expect((await resolver(_request('/posts/:slug', '/posts/a')))?.title, 'Model /posts/a');
    });

    test('a matched resolver owns its route, including a null answer', () async {
      final resolver = dvRoutePageResolver(
        <String, DVPageDataResolver>{'/': (_) => null},
        fallback: (_) => const DVPageData(title: 'should not be reached'),
      );
      expect(await resolver(_request('/', '/')), isNull);
    });

    test('its routes are resolved on request; every other route stays static', () {
      final resolver = dvRoutePageResolver(<String, DVPageDataResolver>{'/days/:day': (_) => null});
      expect(dvPageResolverIsStatic(resolver, '/days/:day'), isFalse);
      expect(dvPageResolverIsStatic(resolver, '/about'), isTrue);
    });
  });

  group('DVPageData.document', () {
    test('headings, paragraphs and links become the semantic document', () {
      final html = dvRenderPage(
        shell: _shell,
        path: '/',
        data: const DVPageData(title: 'Today', document: <DVDocumentBlock>[
          DVDocumentBlock.heading('Matches', level: 2),
          DVDocumentBlock.paragraph('Two roles fit.'),
          DVDocumentBlock.link('Platform Engineer', 'https://jobs.example.com/1'),
        ]),
      );
      expect(html, contains('<h1>Today</h1>'));
      expect(html, contains('<h2>Matches</h2>'));
      expect(html, contains('<p>Two roles fit.</p>'));
      expect(html, contains('<a href="https://jobs.example.com/1">Platform Engineer</a>'));
    });

    test('text is escaped and an unsafe link is written as plain text', () {
      final html = dvRenderPage(
        shell: _shell,
        path: '/',
        data: const DVPageData(title: 'T', document: <DVDocumentBlock>[
          DVDocumentBlock.paragraph('<script>alert(1)</script>'),
          DVDocumentBlock.link('click', 'javascript:alert(1)'),
          DVDocumentBlock.link('protocol-relative', '//evil.example'),
        ]),
      );
      expect(html, isNot(contains('<script>alert(1)</script>')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('javascript:')));
      expect(html, isNot(contains('href="//evil.example"')));
      expect(html, contains('<p>click</p>'));
    });

    test('a document survives the page cache', () {
      const data = DVPageData(title: 'T', document: <DVDocumentBlock>[
        DVDocumentBlock.heading('H', level: 3),
        DVDocumentBlock.link('L', '/jobs/1'),
        DVDocumentBlock.paragraph('P'),
      ]);
      final back = DVPageData.fromJson(data.toJson());
      expect(back.document.map((b) => b.toJson()).toList(), data.document.map((b) => b.toJson()).toList());
    });
  });

  // ChopDesk (Dartvel 3.47.11): its sign-in and landing pages answer with a
  // DVPageData document that says what the app's page says. On a web-server
  // build that document replaced the page the build captured and laid out,
  // so with SSR-first the visitor saw a plain reading column until the app
  // took over (handover diff 10-18%). When the capture already holds every
  // word of the data's document, the captured page is the document, laid out
  // in the app's look, under the data's head.
  group('DVPageData.document with SSR-first', () {
    final String ssrShell = _shell.replaceFirst(
      '</head>',
      '${dvSsrFirstHead(background: '#ffffff', darkBackground: '#000000', accent: '#b83a12')}</head>',
    );
    const String laidOut = '<div class="dvl"><style class="dvl-style">.dvl{}</style>'
        '<h1>Sign in to your desk</h1><p>Owners use their email. Staff can use the phone number the owner set up for them.</p>'
        '<p><a href="/sign-up">Set up your restaurant</a></p><label>Email or phone number</label><input name="Email or phone number"></div>';
    const DVRoutePage route = DVRoutePage(route: '/sign-in', title: 'Sign in — ChopDesk', html: laidOut);
    const DVPageData sameWords = DVPageData(title: 'Sign in', description: 'Sign in to your ChopDesk desk.', document: <DVDocumentBlock>[
      DVDocumentBlock.heading('Sign in to your desk', level: 1),
      DVDocumentBlock.paragraph('Owners use their email.  Staff can use the phone number the owner set up for them.'),
      DVDocumentBlock.link('Set up your restaurant', '/sign-up'),
    ]);

    test('a document the capture already says is served as the laid-out capture, under the data head', () {
      final String html = dvRenderPage(shell: ssrShell, path: '/sign-in', data: sameWords, route: route);
      expect(html, contains('class="dvl"'));
      expect(html, contains('name="Email or phone number"'));
      expect(html, contains('<title>Sign in</title>'));
      expect(html, contains('Sign in to your ChopDesk desk.'));
    });

    test('a document with words the capture does not have is served as the document', () {
      const DVPageData more = DVPageData(title: 'Menu', document: <DVDocumentBlock>[
        DVDocumentBlock.heading('Sign in to your desk', level: 1),
        DVDocumentBlock.paragraph('Jollof rice, N2,500, sold out today'),
      ]);
      final String html = dvRenderPage(shell: ssrShell, path: '/sign-in', data: more, route: route);
      expect(html, isNot(contains('class="dvl"')));
      expect(html, contains('Jollof rice, N2,500, sold out today'));
    });

    test('a link the capture has under another address is not the same words', () {
      const DVPageData moved = DVPageData(title: 'Sign in', document: <DVDocumentBlock>[
        DVDocumentBlock.link('Set up your restaurant', '/start'),
      ]);
      final String html = dvRenderPage(shell: ssrShell, path: '/sign-in', data: moved, route: route);
      expect(html, isNot(contains('class="dvl"')));
      expect(html, contains('href="/start"'));
    });

    test('without SSR-first the document is served as before', () {
      final String html = dvRenderPage(shell: _shell, path: '/sign-in', data: sameWords, route: route);
      expect(html, isNot(contains('class="dvl"')));
      expect(html, contains('<h1>Sign in</h1>'));
    });
  });
}
