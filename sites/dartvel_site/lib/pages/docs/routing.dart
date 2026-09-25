import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel routing: file pages, links and layouts',
  description: 'Add a page by adding a file, and its URL comes from where the '
      'file lives. Link through a typed DVRoutes target, so a moved '
      'page is a compile error.',
  showAppBar: false,
)
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
          id: 'config-routes',
          title: 'Or declare routes in a file, if you prefer',
          children: <Widget>[
            DocsText('A file under lib/pages is the short way. A route can '
                'also be declared in code, in lib/routes.dart, which suits a '
                'screen that is not a page of its own, a path built from '
                'something else, or a codebase that already keeps its routes '
                'in one place.'),
            DocsCode('routing-config'),
            Bullets(<String>[
              '`dartvel routes` reads the file, so each route gets a typed '
                  'DVRoutes target beside the pages\' own. One router, one '
                  'DVRoutes, whichever way a route was declared.',
              'DVRoute nests through routes:. A nested path joins its '
                  'parent\'s, so :person under /roasters is '
                  '/roasters/:person.',
              'DVShellRoute and DVStatefulShellRoute wrap children in shared '
                  'chrome, and take a redirect that may be async, so a '
                  'session check shows the pending view and never a blank '
                  'screen.',
              'DVRoute is a screen, DVShellRoute wraps its children in a '
                  'frame, and DVStatefulShellRoute keeps a stack per branch. '
                  'DVGoRoutes mounts a GoRoute list you already have.',
              'dartvel.routes in pubspec.yaml points at another file. A route '
                  'the reader cannot parse stops the build with DV-ROUTE-003. '
                  'It is not skipped: a skipped route still runs, with no '
                  'typed target and no page on the web.',
            ]),
          ],
        ),
        DocsSection(
          id: 'page-body',
          title: 'Write logic in a page body',
          children: <Widget>[
            DocsText('A page function can have a block body, with signals and '
                'local variables before it returns its widgets.'),
            DocsCode('pages-block-body'),
            Bullets(<String>[
              'The function stays private. Generation writes the public page '
                  'and its route.',
              'Helpers declared in the page\'s own file still resolve after '
                  'generation moves the body.',
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
              'target.withQuery(...) adds a query and stays a route. '
                  '/sign-in?from=/account is two generated targets in one '
                  'call, so either page moving is a compile error. Values '
                  'are encoded.',
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
            DocsText('A path no route serves renders a 404 page in your '
                'app\'s theme, with a link to the home page. You write '
                'nothing for that.'),
            DocsText('To send unknown paths somewhere instead, name where:'),
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  notFoundRedirect: /',
            ]),
            Bullets(<String>[
              'For a page of your own, put one at the route you redirect to.',
              'On a static host, `dartvel build web` also writes 404/index.html '
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
          id: 'layouts-and-mounting',
          title: 'Layouts, tabs and somebody else\'s router',
          children: <Widget>[
            DocsSubheading('Tabs from a folder'),
            DocsText('A _layout.dart that extends DartvelTabsLayout makes its '
                'folder a set of tabs. A detail page is pushed inside its tab, '
                'and back pops inside the tab on screen.'),
            DocsSubheading('Mount into your GoRouter'),
            DocsText('dartvelRoutes(at: \'/app\') returns every Dartvel route '
                'under a prefix for your own GoRouter. DV.Navigation and '
                'DVNavLink place Dartvel targets under it and leave your paths '
                'alone.'),
            UpstreamCredit('go_router', lead: 'The generated router is built on'),
            DocsSubheading('Deep links'),
            DocsText('List your domains under dartvel.deepLinks in '
                'pubspec.yaml. `dartvel build web` writes assetlinks.json and '
                'apple-app-site-association, and '
                '`dartvel doctor --target android,ios` checks the deployed files.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Pages'),
            DocsStatus('Routing', missing: <String>[
              'Typed DVRoutes targets for routes inside DVGoRoutes.',
              'A prefix-mounted navigator for apps that do not use go_router.',
            ]),
          ],
        ),
      ],
    );
