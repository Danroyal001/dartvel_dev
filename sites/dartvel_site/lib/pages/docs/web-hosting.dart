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
        'dartvel build web writes static files you can upload to any shared '
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
              <String>['offline/index.html, 404/index.html', 'The offline and '
                  'not-found pages'],
              <String>['sitemap.xml, robots.txt', 'Search engines, when '
                  'seo.siteUrl is set'],
              <String>['.htaccess', 'Apache and LiteSpeed rules, when '
                  'seo.siteUrl is set'],
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
              'index.html and main.dart.js are never cached, so a new upload '
                  'reaches returning visitors.',
              'Put your own web/.htaccess in the project and the build copies '
                  'yours instead.',
            ]),
          ],
        ),
        DocsSection(
          id: 'pwa',
          title: 'Install it as an app, and use it offline',
          children: <Widget>[
            Bullets(<String>[
              'dartvel build web writes the manifest, icons from web/icon.png, '
                  'a service worker and an offline page.',
              'A change sent while offline is queued in the browser and sent in '
                  'order when the network is back. CI checks this in Chrome on '
                  'every push.',
              'The install prompt reports what the visitor chose, and can be '
                  'offered again after a No.',
            ]),
            DocsStatus('PWA'),
          ],
        ),
        DocsSection(
          id: 'other-hosts',
          title: 'Other static hosts',
          children: <Widget>[
            Bullets(<String>[
              'Any host works if it serves index.html for paths with no file.',
              'dartvel deploy --target web --provider netlify runs the provider\'s '
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
      ],
    );
