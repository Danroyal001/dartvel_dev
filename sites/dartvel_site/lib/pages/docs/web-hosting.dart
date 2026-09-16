import 'package:flutter/material.dart';

import '../../components/docs_cli_reference.dart';
import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Host a Dartvel web build on Apache or LiteSpeed', showAppBar: false)
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
          id: 'other-hosts',
          title: 'Other static hosts',
          children: <Widget>[
            Bullets(<String>[
              'Any host works if it serves index.html for paths with no file.',
              'dartvel deploy --target web --provider netlify runs the provider\'s '
                  'own CLI. firebase, vercel and cloudflare work the same way.',
            ]),
          ],
        ),
      ],
    );
