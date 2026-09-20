import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Expo for Flutter',
  description: 'Expo for Flutter: dartvel dev pairs a phone with a QR code, '
      'dartvel build ships to the stores, and over-the-air patches land '
      'without a review. Plus the backend Expo leaves to you.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.9,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _vsExpoPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          glow: true,
          children: <Widget>[
            Eyebrow('EXPO FOR FLUTTER'),
            Heading(
              'Expo for Flutter, with the backend included.',
              level: 1,
            ),
            Body('Expo is the reason React Native is pleasant to work in: one '
                'command to run the app on a real phone, builds on somebody '
                "else's machines, store submission, and updates that reach "
                'users without a review. Flutter has none of that in the box. '
                'Dartvel is that layer, and it goes further, because an Expo '
                'app still needs a server somebody else writes.'),
            Bullets(<String>[
              'dartvel dev serves your app and prints a QR code. Scan it and '
                  'the phone is paired. No flag, no second command.',
              'dartvel build android, ios, macos, windows, linux, tizen, '
                  'webos, tvos, vscode. Add --cloud and it runs on our '
                  'machines instead of yours.',
              'dartvel deploy --store play, testflight, app-store, '
                  'firebase-app-distribution.',
              'dartvel updates patch serves a fix over the air, from Cloud or '
                  'from your own web-server binary.',
            ]),
            CodeBlock(<String>[
              'dartvel dev            # QR code, pair, hot reload',
              'dartvel build android  # or ios, tizen, webos, vscode',
              'dartvel deploy --store play',
              'dartvel updates patch  # no store review',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('SIDE BY SIDE'),
            Heading('What each one gives you.'),
            DocsTable(
              columns: <String>['', 'Expo', 'Dartvel'],
              rows: <List<String>>[
                <String>['Language', 'TypeScript', 'Dart, front and back'],
                <String>['Run on a device', 'expo start, Expo Go', 'dartvel dev, QR code, pairing always on'],
                <String>['Cloud builds', 'EAS Build', 'dartvel build --cloud (Cloud is not open yet)'],
                <String>['Store submission', 'EAS Submit', 'dartvel deploy --store'],
                <String>['Over the air', 'EAS Update', 'dartvel updates patch, from Cloud or your own binary'],
                <String>['Backend', 'None. Bring your own', '@DVBackendFunction, data models, auth, queues, mail'],
                <String>['Database', 'None', 'SQLite locally, Postgres and MySQL adapters'],
                <String>['Admin', 'None', 'Studio, served by your own binary'],
                <String>['TVs and embedded', 'No', 'Tizen, webOS, tvOS, Android TV, embedded Linux'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THE DIFFERENCE'),
            Heading('An Expo app still needs a server. A Dartvel app is one.'),
            Body('This is the part that is not a feature comparison. Expo '
                'builds and ships a client; what that client talks to is your '
                'problem, and the usual answer is a second repository in a '
                'second language with a second deployment and a hand-written '
                'API client in between. In Dartvel a backend function is a '
                'Dart function, and the client that calls it is generated from '
                'it, so renaming an argument breaks the build instead of '
                'production.'),
            CodeBlock(<String>[
              '@DVBackendFunction()',
              'Future<Invoice> _issue(String orderId) async { ... }',
              '',
              '// in the app, typed, generated, no fetch and no string URL',
              'final Invoice invoice = await issue(orderId: order.id);',
            ]),
            Bullets(<String>[
              'Data models are offline-first and realtime by default, so a '
                  'list updates itself and survives a tunnel.',
              'Auth, sessions, second factors, policies and an admin come '
                  'with the framework instead of from four packages.',
              'One binary from dartvel build web-server runs the site, the '
                  'API and Studio, with SQLite created beside it.',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('Where Expo is ahead today.'),
            Bullets(<String>[
              'EAS is a running service with paid plans. Dartvel Cloud is '
                  'built and not open: --cloud needs a token nobody can buy '
                  'yet. Local builds, store uploads and patches from your own '
                  'binary are free and work now.',
              "Expo's ecosystem of config plugins and prebuilt modules is "
                  'years old and very large.',
              'React Native has more people to hire and more answers already '
                  'written down.',
            ]),
            VersusFair('Expo is very good at what it does, and Dartvel copies '
                'the shape of it on purpose. The claim here is not that Expo '
                'is worse. It is that a Flutter developer has had nothing of '
                'the kind, and that a mobile toolchain without a backend '
                'leaves half the application to you.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Start an app', '/docs'),
              GhostLink('What ships today', '/features'),
              GhostLink('Build without a Mac', '/flutter-without-a-mac'),
            ], spacing: 12),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/expo')]),
        SiteFooter(),
      ], spacing: 0),
    );
