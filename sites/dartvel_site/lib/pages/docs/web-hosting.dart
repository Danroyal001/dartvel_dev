import 'package:flutter/material.dart';

import '../../components/docs_cli_reference.dart';
import '../../components/site.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Host a Dartvel web build on Apache or LiteSpeed',
  description: 'dartvel build web writes static files you can upload to any '
      'shared host, and the .htaccess it writes makes deep links and '
      'caching work on Apache or LiteSpeed.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsWebHostingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docswebhosting,
      lead: <String>[
        '`dartvel build web` writes static files you can upload to any shared '
            'host.',
        'On Apache or LiteSpeed, the .htaccess it writes makes deep links and '
            'caching work.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'build',
          title: 'Build the site',
          children: <Widget>[
            DocsShell(<String>['dartvel build web']),
            DocsText('Upload the contents of build/web to your web root.'),
          ],
        ),
        DocsSection(
          id: 'output',
          title: 'What the build writes',
          children: <Widget>[
            DocsTable(columns: <String>[
              'File',
              'For',
            ], rows: <List<String>>[
              <String>['index.html', 'The app shell, with the title, '
                  'description, Open Graph tags and splash'],
              <String>['<route>/index.html', 'One page per route, so a deep '
                  'link and a crawler get real HTML'],
              <String>['manifest.json, icons/', 'The installable PWA'],
              <String>['flutter_service_worker.js', 'Offline caching, '
                  'replaced by Dartvel\'s worker'],
              <String>['offline/index.html, 404/index.html', 'The not-found '
                  'and offline pages, which are routes of your app'],
              <String>['404.html', 'The not-found page again, for the hosts '
                  'that look for that name'],
              <String>['sitemap.xml, robots.txt', 'Search engines, when '
                  'seo.siteUrl is set'],
              <String>['.htaccess', 'Apache and LiteSpeed rules: routes, '
                  'caching and security headers'],
              <String>['_headers', 'The same security headers for Netlify '
                  'and Cloudflare Pages'],
            ]),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  seo:',
              '    siteUrl: https://example.com',
            ]),
            Bullets(<String>[
              'Routes with parameters get pages for the paths your models list.',
              'Set pwa.enabled: false to leave out the manifest and worker.',
            ]),
            DocsText('Until the app has loaded, a visitor sees the splash: '
                'your logo, a pulsing Loading line and a loading bar that '
                'follows the real downloads. They go when the app has drawn '
                'its first screen. Earlier versions showed a picture of each '
                'page instead; it was removed because it looked finished but '
                'did nothing when tapped. If your pubspec still has '
                'web.firstFrame, the build ignores it and says so: delete it.'),
            DocsText('Every web build is compiled twice: Chrome, Edge and '
                'Chrome for Android run the WebAssembly version, other '
                'browsers the JavaScript one. Each page loads its own code '
                'when it is first shown. The page and the splash are the '
                'same either way.'),
            DocsText('On the web-server build, the WebAssembly version draws on '
                'a second thread, which keeps scrolling smooth on slow phones. '
                'That needs two headers the build turns on by itself unless '
                'your site loads scripts or frames from another site, or '
                'opens sign-in or payment popups there; the build says when '
                'it leaves them off.'),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  web:',
              '    wasm: false                 # JavaScript only',
              '    crossOriginIsolated: false  # never send the two headers',
            ]),
          ],
        ),
        DocsSection(
          id: 'htaccess',
          title: 'The .htaccess for Apache and LiteSpeed',
          children: <Widget>[
            DocsText('This is the file the build writes. LiteSpeed reads the '
                'same rules.'),
            CodeBlock(kApacheConfig),
            Bullets(<String>[
              'Existing files are served as they are. Every other path loads '
                  'the app, which routes it.',
              'index.html, main.dart.js and the service worker are checked '
                  'with the server on every visit, so a new upload reaches '
                  'returning visitors.',
              'Every response gets X-Content-Type-Options, X-Frame-Options '
                  '(SAMEORIGIN) and a Referrer-Policy, the same headers the '
                  'Dartvel server sends. A header your host already sets is '
                  'kept.',
              'Put your own web/.htaccess or web/_headers in the project and '
                  'the build copies yours instead.',
              'The build rewrites its own .htaccess every time, so fixes to '
                  'the rules reach you. Delete the first line of the copy in '
                  'build/web and later builds leave your edits alone.',
            ]),
          ],
        ),
        DocsSection(
          id: 'pwa',
          title: 'Install it as an app, and use it offline',
          children: <Widget>[
            Bullets(<String>[
              '`dartvel build web` writes the manifest, the icons and a service '
                  'worker. A page the worker cannot reach opens /offline, a page '
                  'of your app that says where you were.',
              'Every icon comes from one image, `dartvel.pwa.icon` (or assets/icon.png): '
                  'the tab icon (favicon.png), the home-screen icon '
                  '(apple-touch-icon.png) and the four install icons. With no '
                  'image the build draws a monogram of your app\'s name and says so. '
                  'Flutter\'s template logo, package name, "A new Flutter project." '
                  'and blue are never shipped: the name, description and colours '
                  'come from dartvel.pwa, then dartvel.seo.',
              'A change sent while offline is queued in the browser and sent in '
                  'order when the network is back. CI checks this in Chrome on '
                  'every push.',
              'The install prompt reports what the visitor chose, and can be '
                  'offered again after a No.',
              'A second visit loads from the phone: the worker keeps the app, '
                  'its fonts, the renderer and every page part, and the page '
                  'hands it what the first visit downloaded. Pages themselves '
                  'always come from the network first, so they stay fresh.',
              'A release reaches people on their next visit. The page asks for '
                  'the app at its build (main.dart.js?v=<build>), so new HTML '
                  'is never paired with the old code, and only files whose '
                  'contents changed are downloaded again.',
              'On by default. `dartvel.pwa.enabled: false` turns it off; '
                  '`dartvel.pwa.precacheRoutes` sets how many pages are saved '
                  'on the first visit (25 by default, or `true` for all).',
            ]),
            DocsStatus('PWA'),
          ],
        ),
        DocsSection(
          id: 'fonts',
          title: 'Fonts that download fast',
          children: <Widget>[
            DocsText('The engine waits for every font before it draws, so the '
                'build makes them as small as it can without changing what '
                'your pages show.'),
            Bullets(<String>[
              'Fonts go out as WOFF2, under a name that changes with their '
                  'contents, so a browser keeps them for a year.',
              'Text fonts keep Latin (Yoruba, Igbo and Hausa letters '
                  'included), common symbols and every character your own '
                  'code and content use. Anything else someone types is drawn '
                  'with a Noto font the engine fetches for it.',
              'Static weights are dropped when a variable font of the same '
                  'design draws them, and a font family nothing names is not '
                  'downloaded.',
              'Roboto, which Flutter otherwise fetches from fonts.gstatic.com, '
                  'comes from your own site.',
              'The build prints what it saved: fonts: 1.3 MB -> 387 KB.',
            ]),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  web:',
              '    fonts:',
              "      characters: ['U+0400-04FF']   # also keep Cyrillic",
              '      # subset: false, useVariable: false, dropUnused: false,',
              '      # roboto: false; or fonts: false for none of it',
            ]),
          ],
        ),
        DocsSection(
          id: 'other-hosts',
          title: 'Other static hosts',
          children: <Widget>[
            Bullets(<String>[
              'Any host works if it serves index.html for paths with no file.',
              '`dartvel deploy --target web --provider netlify` runs the provider\'s '
                  'own CLI. firebase-hosting, vercel and cloudflare work the same way.',
            ]),
          ],
        ),
        DocsSection(
          id: 'find-in-page',
          title: 'Find text with Ctrl+F',
          children: <Widget>[
            DocsText('Ctrl+F (Cmd+F on a Mac), and Find in page from a phone '
                'browser\'s menu, find text on a Dartvel web page. The page '
                'scrolls to the paragraph that matched and highlights it.'),
            DocsText('Flutter draws the page\'s words on a canvas, and the '
                'browser searches the document. So every page keeps a copy of '
                'its text in the document where the browser can search it:'),
            Bullets(<String>[
              'The build writes each page\'s text into its HTML for crawlers, '
                  'no-script readers and printers. Each paragraph is marked '
                  'hidden="until-found", which the browser searches and does '
                  'not draw.',
              'When a match lands in a paragraph, the browser fires '
                  'beforematch. Dartvel scrolls the Flutter page to that '
                  'paragraph, highlights it, and hides the copy again.',
              'After you navigate, or when the page\'s content changes, the '
                  'copy is rewritten from what the page has drawn. Find and '
                  'printing follow the page on screen.',
              'There is nothing to add to a page. @DVPage(findable: false) '
                  'keeps a page\'s text out of the document.',
            ]),
            DocsText('A browser match names the paragraph and not the word, so '
                'the page scrolls to the paragraph. It works in Chrome, Edge '
                'and other Chromium browsers, and in Firefox 139 and later. '
                'Safari has not been checked yet. A browser without '
                'until-found finds nothing on the page, as before.'),
            DocsText('Esc closes the find bar from the page as well as from '
                'the bar. A page answers Esc only when it has something open '
                'to close, such as a dialog, a menu or the text selection '
                'menu. Otherwise the key goes to the browser.'),
            DocsText('A list builds only the rows near the screen, so text in '
                'a row that has not been built yet is not found.'),
            DocsNote('Planned',
                'An in-app find bar in the page shell, for native builds and '
                'for browsers without until-found. Generated record tables '
                'that register the rows they have not built, so a match in a '
                'row off screen is found too. Neither is built yet.'),
            ExternalLink('Read the find in page proposal',
                kFindInPageProposalUrl),
          ],
        ),
        DocsSection(
          id: 'heading-links',
          title: 'Link to a heading',
          children: <Widget>[
            DocsText('An address ending in #heading-id opens the page at that '
                'heading, on the web and in a native app, as it does on any '
                'other web page. Flutter ignores the part after #, so a '
                'Dartvel page does this itself.'),
            Bullets(<String>[
              'Every heading gets an id from its words: lower case, '
                  'punctuation dropped, spaces as hyphens. "Find text with '
                  'Ctrl+F" is #find-text-with-ctrlf.',
              'A heading that repeats an earlier one is numbered from 2: the '
                  'second "Setup" is #setup-2.',
              'Headings are the text a page marks with semanticHeading(n). '
                  'There is nothing to add to a page.',
              'A page that loads its content later still opens at the '
                  'heading: Dartvel looks for it again as the page draws.',
            ]),
            DocsText('Try it: this button goes to '
                '/docs/web-hosting#find-text-with-ctrlf.'),
            GhostLink('Go to "Find text with Ctrl+F"',
                '/docs/web-hosting#find-text-with-ctrlf'),
          ],
        ),
      ],
    );
