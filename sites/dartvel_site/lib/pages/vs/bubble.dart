import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel vs Bubble',
  description: 'Dartvel vs Bubble: a visual builder with a backend built in, '
      'on more platforms, that writes real Dart you own and can take with '
      'you when the drag-and-drop runs out.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.9,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsBubblePage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('DARTVEL VS BUBBLE'),
            Heading(
              'Build it visually, and still own the code underneath.',
              level: 1,
            ),
            Body('Bubble is one of the most complete no-code platforms: a '
                'visual page builder, workflows, a database, auth, an API '
                'connector, plugins, an AI agent that generates and edits '
                'apps, and native iOS and Android apps, whose editor is in '
                'beta. Studio is '
                'the same shape. The difference is what you are left holding: '
                'a Bubble app runs on Bubble, and a Dartvel app is a Dart '
                'project in your own repository that happens to have a '
                'builder on top of it.'),
            Bullets(<String>[
              'A page built in Studio is a document your app serves, and the '
                  'same project is Dart you can open, diff and review.',
              'Frontend and backend function builders are free, in the Studio '
                  'your own binary serves.',
              'When the builder runs out, you write the function in Dart '
                  'beside the ones it generated. There is no ceiling and no '
                  'export.',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('SIDE BY SIDE'),
            Heading('What each one gives you.'),
            DocsTable(
              columns: <String>['', 'Bubble', 'Dartvel'],
              rows: <List<String>>[
                <String>['Page builder', 'Yes, and very good', 'Studio, free, served by your own binary'],
                <String>['Logic', 'Workflows in the editor', 'Frontend and backend function builders, free'],
                <String>['Escape hatch', 'Plugins, the API Connector, and JavaScript through plugins', 'Write Dart beside what the builder made'],
                <String>['Backend', 'Built in', 'Built in, and it is yours'],
                <String>['Database', "Bubble's own, and external SQL databases through the SQL Database Connector", 'SQLite, Postgres or MySQL, wherever you run it'],
                <String>['Hosting', "Bubble's servers, or a dedicated instance Bubble runs on AWS", 'One binary, on any Linux, macOS or Windows box'],
                <String>['Targets', 'Web, and native iOS and Android in beta', 'Web, Android, iOS, desktop, TVs, browser and editor extensions'],
                <String>['Pricing', 'Plans metered by workload units', 'The framework is free; Cloud builds will be paid'],
                <String>['Leaving', 'A rewrite. Data exports; the app does not', 'You already have the repository'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THE CEILING'),
            Heading('Every visual builder has one. This one has a door in it.'),
            Body('The moment that decides a no-code project is the one where '
                'the thing you need is not in the editor. On Bubble that is a '
                'plugin you find or write in JavaScript, a workaround, or a '
                'rebuild somewhere else. In Studio '
                'the builder generates a function in your project, and the '
                'next one you write by hand sits beside it and is called the '
                'same way.'),
            CodeBlock(<String>[
              '// what the builder made, in your repository',
              '@DVBackendFunction()',
              'Future<Order> _placeOrder(String itemId, int quantity) async {',
              '  // and what you added when the builder ran out',
              '  await DV.Notifications.mail.send(receipt);',
              '  return order.save();',
              '}',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Bubble is ahead today.'),
            Bullets(<String>[
              'Bubble has been running for over a decade, with a plugin '
                  'ecosystem, an agency network and a marketplace. Studio has '
                  'no marketplace open yet.',
              'Its editor is deeper: responsive rules, reusable elements, '
                  'workflow branching, a debugger, version control and '
                  'collaborators, built over years.',
              "Bubble's AI agent generates a first version of an app from a "
                  'description and edits it on request, inside the editor.',
              'Bubble hosts your app. Dartvel gives you a binary, and running '
                  'it is your job until Cloud opens.',
              'You can build a working Bubble app knowing nothing about code. '
                  'Studio asks less of you than Dart does, and it does not ask '
                  'nothing.',
            ]),
            Objection(
              'Is Dartvel no-code then?',
              'No. It is a framework with a builder on it. The bet is that '
                  'the people who outgrow no-code and the people who want to '
                  'start without writing Dart should not have to be on two '
                  'different platforms.',
            ),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('See Studio', '/studio'),
              GhostLink('What ships today', '/features'),
            ], spacing: 12),
            VersusChecked('Bubble', 'https://manual.bubble.io/llms.txt',
                '2026-09-25'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/bubble')]),
        SiteFooter(),
      ], spacing: 0),
    );
