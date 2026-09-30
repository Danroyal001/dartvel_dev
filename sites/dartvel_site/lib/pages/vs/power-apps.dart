import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Every Power Apps claim here was read against Microsoft's own documentation
// and pricing page on the date VersusChecked shows; every Dartvel claim
// against the code and docs/spec-status.json on the same day. A Power Apps
// fact that could not be found in Microsoft's documentation is not stated.
@DVPage(
  title: 'Dartvel vs Power Apps',
  description: 'Dartvel vs Microsoft Power Apps: a visual builder and a '
      'backend in a Dart project you own and host yourself, set beside a '
      'low-code platform that runs in Microsoft 365 and is licensed per user.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsPowerAppsPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('DARTVEL VS POWER APPS'),
            Heading(
              'Business apps built visually, in a project you own and host.',
              level: 1,
            ),
            Body('Power Apps is how a Microsoft 365 organisation builds its '
                'own apps: canvas apps written in Power Fx, model-driven apps '
                'over Dataverse, over a thousand connectors to the systems a '
                'company already runs, and Entra ID sign-in, governance and '
                'Copilot on top. Dartvel covers the same ground from the '
                'other end. Studio builds pages, data models and functions '
                'in a browser, and what it builds is a Dart project in your '
                'repository that compiles to one server you run and to '
                'native apps you publish under your own name.'),
            Bullets(<String>[
              'Every Power Apps user needs a licence: Premium is 20 US '
                  'dollars per user per month. Dartvel is free to build and '
                  'run, with no per-user fee.',
              'A Power Apps app runs in Microsoft\'s cloud and in its player '
                  'apps. A Dartvel app is a server binary on your own machine '
                  'and apps built for phones, desktops, the web and TVs.',
              'Power Fx is the Power Platform formula language. Dartvel is '
                  'Dart, from the page builder down to the database.',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('SIDE BY SIDE'),
            Heading('What each one gives you.'),
            DocsTable(
              columns: <String>['', 'Power Apps', 'Dartvel'],
              rows: <List<String>>[
                <String>['Builder', 'Canvas and model-driven app designers, and code apps in React or Vue', 'Studio: pages, data models and records, free, served by your own binary'],
                <String>['Logic', 'Power Fx formulas, Power Automate flows, and Dataverse plug-ins in C#', 'Frontend and backend function builders, and Dart beside them'],
                <String>['Data', 'Dataverse, plus over a thousand connectors and custom ones from OpenAPI', 'Data models on SQLite, Postgres or MySQL, and outbound HTTP to the hosts you declare'],
                <String>['Sign-in', 'Entra ID accounts, with outside users as guests', 'Your own accounts, passkeys, a second factor, and Microsoft, SAML or LDAP sign-in'],
                <String>['Hosting', "Microsoft's cloud, in a tenant's environments", 'One binary, on any Linux, macOS or Windows server'],
                <String>['Runs on', 'Browsers, and the Power Apps players for iOS, Android and Windows', 'Web, Android, iOS, macOS, Windows, Linux, TVs, and browser and editor extensions'],
                <String>['Your own app', 'Wrap packages a canvas app for iOS and Android; each user still needs a licence', 'Every build is your own app, in your own store listing'],
                <String>['Offline', 'In the native players, built in for Dataverse', 'Offline data models that sync when the server is back, partial'],
                <String>['Pricing', 'Premium 20 US dollars per user per month, or 10 per active user per app', 'Free; Cloud builds will be paid'],
                <String>['Leaving', 'An exported app imports only into another Power Apps environment', 'You already have the repository'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THE LICENCE'),
            Heading('Who pays when the app gets more users.'),
            Body('A Power Apps licence is per person using the app, and a '
                'premium connector or Dataverse makes the app premium. An '
                'app for fifty people inside the company costs a thousand '
                'US dollars a month at list price, and a site for customers '
                'is a separate product, Power Pages. A Dartvel app has '
                'no per-user charge: the cost of a thousand users is the '
                'server they use.'),
            CodeBlock(<String>[
              '// a data model: its form, table and admin are generated',
              '@DVModel()',
              'class const _Request({',
              '  required final String id,',
              '  required final String title,',
              "  final String status = 'open',",
              '});',
              '',
              '// Request.Form(), Request.Table() and Request.Admin()',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Power Apps is ahead today.'),
            Bullets(<String>[
              'If your company runs on Microsoft 365, Power Apps is already '
                  'there: SharePoint lists, Teams, Outlook, Excel and Entra '
                  'ID are connectors and sign-in you do not set up, and '
                  'Dartvel reaches them only through their APIs.',
              'Over a thousand connectors, an on-premises data gateway, data '
                  'loss prevention policies, managed environments and '
                  'Dataverse security roles are years of governance an IT '
                  'department can switch on. Dartvel has policies and '
                  'tenancy, and none of the admin centre around them.',
              'Copilot builds a first version of an app and its tables from '
                  'a description. Studio has no AI that builds an app for you.',
            ]),
            Objection(
              'Do I have to host it myself?',
              'Today, yes: Dartvel gives you one server binary, and running '
                  'it is your job until Dartvel Cloud opens. Power Apps '
                  'needs no server of yours at all.',
            ),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('See Studio', '/studio'),
              GhostLink('What ships today', '/features'),
            ], spacing: 12),
            VersusChecked('Power Apps',
                'https://learn.microsoft.com/en-us/power-apps/powerapps-overview',
                '2026-09-30'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/power-apps')]),
        SiteFooter(),
      ], spacing: 0),
    );
