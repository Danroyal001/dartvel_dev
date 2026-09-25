import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Flutter without a Mac',
  description: 'Flutter without a Mac: what you can build, run and ship from '
      'a Windows or Linux machine today, what still needs Xcode, and three '
      'routes to an iOS build when you do not own a Mac.',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.9,
    changeFrequency: DVSitemapChangeFrequency.monthly,
  ),
)
@pragma('vm:entry-point')
Widget _flutterWithoutAMacPage(BuildContext context) =>
    const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          grain: true,
          children: <Widget>[
            Eyebrow('FLUTTER WITHOUT A MAC'),
            Heading(
              'Flutter without a Mac: what works, and what the Mac is '
              'actually for.',
              level: 1,
            ),
            Body('Apple requires its own tools to compile and sign an iOS or '
                'macOS application, and those tools run on macOS. That is the '
                'whole of the restriction, and it covers running on an iPhone '
                'as well as building for one. Everything else needs no Apple '
                'hardware: writing the app, the website, Android, the Windows '
                'or Linux desktop, Samsung TVs, the backend, the database and '
                'the admin.'),
            Bullets(<String>[
              'On Windows or Linux: `dartvel dev`, and `dartvel build web`, '
                  'web-server, android, tizen and vscode. Flutter does not '
                  'cross-compile desktops, so windows builds on Windows, and '
                  'linux and sony-elinux build on Linux.',
              'The Mac is needed for `dartvel build ios`, macos and tvos, and '
                  'for running a development build on an iPhone or the iOS '
                  'simulator.',
              'Testing on a phone without a Mac means an Android phone. See '
                  'below.',
            ]),
            UpstreamCredits(ids: <String>[
              'tizen', 'elinux', 'vscode',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('WHAT YOU CAN DO'),
            Heading('Everything except the Apple compile step.'),
            DocsTable(
              columns: <String>['Task', 'Needs a Mac?'],
              rows: <List<String>>[
                <String>['Write the app, hot reload, `dartvel dev`', 'No'],
                <String>['Pair an Android phone over the QR code', 'No'],
                <String>['Pair an iPhone or the iOS simulator', 'Yes, Xcode starts the development build'],
                <String>['`dartvel build web` and web-server', 'No'],
                <String>['`dartvel build android`, and ship to Google Play', 'No'],
                <String>['`dartvel build windows` or linux', 'No Mac, and each on its own operating system'],
                <String>['`dartvel build tizen`, sony-elinux, vscode', 'No'],
                <String>['Backend, database, auth, queues, Studio', 'No'],
                <String>['`dartvel build ios`, macos, tvos', 'Yes, Xcode'],
                <String>['Signing an IPA, and App Store submission', 'Yes, Xcode'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('TEST ON A PHONE'),
            Heading('`dartvel dev` pairs a phone. Without a Mac, that phone runs Android.'),
            Body('`dartvel dev` prints a QR code that pairs a development build '
                'of your app, and every save hot reloads it. On Android the '
                'development build installs like any APK and needs nothing '
                'from Apple. On an iPhone it is a debug build that has to be '
                'started from Xcode or `flutter run`, and in CI the iOS '
                'pairing is proven on the simulator, which also needs a Mac. '
                'Expo users are used to scanning a code with Expo Go on an '
                'iPhone and no Mac; Dartvel has no equivalent of Expo Go.'),
            CodeBlock(<String>[
              'dartvel build android --profile development',
              'dartvel dev',
              '# scan the QR code from the phone',
            ]),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('THREE ROUTES'),
            Heading('Getting an iOS build when you do not own a Mac.'),
            Bullets(<String>[
              'A hosted macOS runner. GitHub Actions gives public '
                  'repositories free macOS minutes, and Dartvel is built and '
                  'verified that way: the iOS and tvOS rows in the build '
                  'status table were produced on a runner, with the artifact '
                  'downloaded and inspected.',
              'A rented Mac. MacStadium, Scaleway and others rent one by the '
                  'hour or the month, and Xcode runs on it exactly as it '
                  'would on your desk.',
              '`dartvel build ios --cloud`. The build runs on our macOS '
                  'workers, the log streams to your terminal, and the IPA '
                  'downloads into build/cloud checked against its SHA-256. '
                  'Cloud is built and not open yet, and it will be paid.',
            ]),
            CodeBlock(<String>[
              '# on a macOS runner, or a Mac you rent',
              'dartvel build ios --format ipa',
              '',
              '# or, when Cloud opens',
              'dartvel build ios --cloud',
            ]),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('HONESTLY'),
            Heading('What this page is not claiming.'),
            Bullets(<String>[
              'Flutter builds and runs iOS apps through Xcode, and Xcode '
                  'runs only on macOS, so Dartvel does not compile iOS on '
                  'Linux or Windows.',
              'Dartvel Cloud is not open. Until it is, the macOS step is a '
                  'runner you configure or a Mac you rent.',
              'An App Store submission needs an Apple Developer account '
                  '(currently 99 USD a year), whoever owns the hardware.',
            ]),
            Objection(
              'Is Expo ahead here?',
              'Yes. Expo Go runs a project on an iPhone with no Mac, and EAS '
                  'Build makes iOS builds on its own machines today. Dartvel '
                  'has no Expo Go, and its Cloud is not open.',
            ),
            Objection(
              'So why is this better than plain Flutter?',
              'Plain Flutter has the same Apple restriction and none of the '
                  'rest: no pairing QR code, no backend, no admin, no store '
                  'submission command, no over-the-air patches, and no build '
                  'command for Samsung TVs, Apple TV or Sony embedded Linux. '
                  'The Mac question is the same; everything around it is '
                  'not.',
            ),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Start an app', '/docs'),
              GhostLink('Build target status', '/docs/building'),
              GhostLink('Expo for Flutter', '/vs/expo'),
            ], spacing: 12),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/flutter-without-a-mac')]),
        SiteFooter(),
      ], spacing: 0),
    );
