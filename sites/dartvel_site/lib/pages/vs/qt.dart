import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel vs Qt',
  description: 'Dartvel vs Qt: phones, desktops, TVs and embedded Linux from '
      'one Dart codebase, with a backend, an admin and no per-seat licence.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsQtPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('DARTVEL VS QT'),
            Heading(
              'Everywhere Qt goes, in Dart, with the server included.',
              level: 1,
            ),
            Body('Qt is the incumbent for software that has to run on a '
                'desktop, a television, a car dashboard and a machine on a '
                'factory floor. It has earned that: thirty years, C++, and a '
                'reach nothing else has matched. The costs are the ones '
                'everybody knows: C++, QML as a second language, a '
                'licensing conversation before a commercial product ships, '
                'and no answer at all for the backend.'),
            Bullets(<String>[
              'One Dart codebase for Android, iOS, macOS, Windows, Linux, '
                  'the web, Samsung TVs, LG webOS, Apple TV, Android TV, '
                  'embedded Linux and a terminal.',
              'Each embedded and TV target is driven by that vendor\'s own '
                  'Flutter embedder, pinned in a fork so it tracks the '
                  'Flutter version Dartvel ships with.',
              'The backend comes with the framework instead of arriving as a '
                  'separate product.',
            ]),
            CodeBlock(<String>[
              'dartvel build linux        # and -cli for a terminal build',
              'dartvel build tizen        # Samsung TVs',
              'dartvel build webos        # LG',
              'dartvel build sony-elinux  # embedded Linux',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('SIDE BY SIDE'),
            Heading('The trade, in plain terms.'),
            DocsTable(
              columns: <String>['', 'Qt', 'Dartvel'],
              rows: <List<String>>[
                <String>['Language', 'C++, and QML for the UI', 'Dart, front and back'],
                <String>['Licence', 'LGPL or commercial, per developer', 'Functional Source License, MIT after the term'],
                <String>['Desktop', 'Mature, native look', 'Flutter on Windows, macOS and Linux'],
                <String>['Embedded and TV', 'Its strongest ground', 'Vendor embedders, forked and pinned. See the status table'],
                <String>['Web', 'Qt for WebAssembly', 'A first-class target, with prerendered HTML and a sitemap'],
                <String>['Backend', 'Not its job', 'Functions, models, auth, queues, mail, an admin'],
                <String>['Tooling', 'Qt Creator, qmake or CMake', 'One dartvel command: dev, build, deploy, test'],
                <String>['Terminal', 'No', 'dartvel build linux-cli renders in a terminal'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('STATUS'),
            Heading('Which targets are proven, and which are not.'),
            Body('Qt has been building for these devices for decades. Some of '
                'these targets are verified on a runner with the artifact '
                'inspected, and some are blocked on a vendor toolchain that '
                'is behind the Dart version Dartvel needs. Every one of them '
                'is written down with what was run and what came out, so you '
                'can check the claim before you make a decision on it.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Build target status', '/docs/building'),
              GhostLink('What ships today', '/features'),
            ], spacing: 12),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Qt is ahead today.'),
            Bullets(<String>[
              'Thirty years of embedded deployments, certifications and '
                  'vendor relationships Dartvel does not have.',
              'C++ where you need C++: real-time constraints, tiny memory '
                  'budgets, and hardware with no Flutter embedder at all.',
              'Qt Creator, Qt Design Studio and the commercial support that '
                  'comes with a licence.',
              'Several of the embedded and TV targets here are honestly '
                  'recorded as unproven or blocked.',
            ]),
            VersusFair('If you are shipping a medical device or a car, Qt is '
                'probably still the answer. The case for Dartvel is a team '
                'that wants one codebase across phones, desktops, the web and '
                'a screen on a wall, in a language a web developer already '
                'reads, with the server in the same repository.'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/qt')]),
        SiteFooter(),
      ], spacing: 0),
    );
