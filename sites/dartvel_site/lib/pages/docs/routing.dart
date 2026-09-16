import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel routing: file pages, links and layouts', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsRoutingPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsrouting,
      lead: <String>[
        'Add a page by adding a file. Its URL comes from where the file lives.',
        'Link to it through a typed DVRoutes target, so a moved page is a '
            'compile error.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'file-pages',
          title: 'Add a page with a file',
          children: <Widget>[
            DocsCode('routing-file-page'),
            DocsTable(columns: <String>[
              'File',
              'URL',
            ], rows: <List<String>>[
              <String>['lib/pages/index.dart', '/'],
              <String>['lib/pages/about.dart', '/about'],
              <String>['lib/pages/blog/index.dart', '/blog'],
              <String>['lib/pages/blog/[id].dart', '/blog/:id'],
              <String>['lib/pages/(marketing)/pricing.dart', '/pricing'],
            ]),
            Bullets(<String>[
              'A folder in parentheses groups files without adding to the URL.',
              'A file is a page when it has @DVPage or ends in .page.dart.',
              'Two files that resolve to one URL stop the build.',
            ]),
          ],
        ),
        DocsSection(
          id: 'params',
          title: 'Read route and query parameters',
          children: <Widget>[
            DocsText('Name a file or folder [id] and read the value from '
                'context.dvParams. Query strings are in context.dvQuery.'),
            DocsCode('routing-params'),
          ],
        ),
        DocsSection(
          id: 'typed-navigation',
          title: 'Navigate with typed DVRoutes targets',
          children: <Widget>[
            DocsText('Generation writes a DVRoutes class with one target per '
                'page. A page with parameters is a function.'),
            DocsShell(<String>[
              'DVRoutes.index               // /',
              'DVRoutes.about               // /about',
              "DVRoutes.blog(id: '42')      // /blog/42",
            ]),
            DocsCode('routing-navigate'),
            Bullets(<String>[
              'context.navigateToPage(target) goes there now.',
              'DV.Navigation.to(target) returns a callback for onTap.',
              'DV.Navigation also has push, back, canGoBack and currentPath.',
            ]),
          ],
        ),
        DocsSection(
          id: 'links',
          title: 'Link with DVNavLink',
          children: <Widget>[
            DocsCode('routing-navlink'),
            Bullets(<String>[
              'Tab, Enter and middle-click behave like a web link.',
              'The target page starts loading after 300 ms on screen.',
              'Hover, or long press on a phone, shows a live preview of the '
                  'page after 550 ms.',
            ]),
            DocsSubheading('Choose when it preloads and previews'),
            DocsCode('routing-navlink-options'),
            Bullets(<String>[
              'DVLinkPreload: none, hover, visible (the default) or immediate.',
              'DVLinkPreview: auto (the default) or none.',
              'DVNavLink.external opens another site and never preloads.',
            ]),
            DocsNote('Keep GlobalKeys inside the page',
                'A preview builds a second live copy of the target page. Keys '
                'shared by the whole program cannot be in two places, so create '
                'them in the page\'s own State.'),
          ],
        ),
        DocsSection(
          id: 'layouts',
          title: 'Share chrome with _layout.dart',
          children: <Widget>[
            DocsText('A _layout.dart wraps every page in its folder and below. '
                'It extends DartvelLayout and places child.'),
            DocsCode('routing-layout'),
            DocsSubheading('Nest a layout in a folder'),
            DocsCode('routing-nested-layout'),
            DocsText('A page under /blog is wrapped by the root layout first, '
                'then by the blog layout.'),
          ],
        ),
        DocsSection(
          id: 'guards',
          title: 'Guard a folder with _guard.dart',
          children: <Widget>[
            DocsCode('routing-guard'),
            Bullets(<String>[
              'A guard runs before every page in its folder and below.',
              'Return a path to redirect, or null to open the page.',
              'For roles and permissions, set policy on @DVPage. See '
                  'Authorization.',
            ]),
          ],
        ),
        DocsSection(
          id: 'loading-error',
          title: 'Show loading and error states',
          children: <Widget>[
            DocsText('Put about.loading.dart and about.error.dart beside '
                'about.dart. Name the classes after the page function: '
                '_aboutPage uses AboutPageLoading and AboutPageError.'),
            DocsCode('routing-loading'),
            DocsCode('routing-error'),
            DocsText('A page without them gets a default spinner and error '
                'message.'),
            DocsStatus('Error, Empty, and Loading States', missing: <String>[
              'No page-level error boundary for errors thrown while the page '
                  'builds.',
              'No per-status-code pages, offline banner or model skeletons.',
            ]),
          ],
        ),
        DocsSection(
          id: 'not-found',
          title: 'Handle unknown URLs',
          children: <Widget>[
            DocsText('Send every unknown path to a page of your choice with '
                'notFoundRedirect.'),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  notFoundRedirect: /',
            ]),
            Bullets(<String>[
              'On a static host, dartvel build web also writes 404/index.html '
                  'for paths the app never loads.',
              'See Static web hosting for the Apache rules.',
            ]),
          ],
        ),
        DocsSection(
          id: 'seo',
          title: 'Set the title and sitemap entry',
          children: <Widget>[
            DocsCode('routing-sitemap'),
            Bullets(<String>[
              'title becomes the browser title and the page\'s SEO title.',
              'sitemap sets this page\'s priority and change frequency in '
                  'sitemap.xml.',
              'The sitemap is written when dartvel.seo.siteUrl is set.',
            ]),
          ],
        ),
        DocsSection(
          id: 'config-routes',
          title: 'Config-based routes (coming)',
          children: <Widget>[
            DocsNote('Coming soon',
                'Routes declared in code, merged with file pages into one '
                'router, are designed and not built yet. This section will '
                'describe them when they ship.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Routing'),
          ],
        ),
      ],
    );
