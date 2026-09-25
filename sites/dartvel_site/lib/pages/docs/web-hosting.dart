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
          title: 'Find in page is planned',
          children: <Widget>[
            DocsNote('Planned',
                'Nothing in this section is built yet. It is a draft proposal from '
                '2026-09-25 that has not been reviewed.'),
            DocsText('Today, Ctrl+F (Cmd+F on a Mac) finds nothing on a '
                'Dartvel web page. The browser searches the document, and '
                'Flutter draws the page\'s words on a canvas, so they are not '
                'in the document. Find in page from a phone browser\'s menu '
                'fails the same way.'),
            DocsText('The proposal has three parts:'),
            Bullets(<String>[
              'The browser\'s own find reaches the page. Each route\'s '
                  'prerendered HTML already carries the page\'s text for '
                  'crawlers, no-script readers and printers, hidden with '
                  'display:none. It would be marked hidden="until-found" '
                  'instead, which the browser can search. When a match lands '
                  'there, the browser fires beforematch, and Dartvel scrolls '
                  'the Flutter page to that paragraph and highlights it.',
              'An in-app find bar in the page shell, for native builds and '
                  'for browsers without until-found. Every page would have it '
                  'with nothing to add, as it has keyboard scrolling today.',
              'Generated record tables would register the rows they have not '
                  'built yet, so a match in a row scrolled off screen is found too.',
            ]),
            DocsText('A browser match names the paragraph and not the word, so '
                'the first part scrolls to the paragraph. Browser support, '
                'Safari in particular, is checked in the prototype before '
                'anything is promised.'),
            ExternalLink('Read the find in page proposal',
                kFindInPageProposalUrl),
          ],
        ),
      ],
    );
