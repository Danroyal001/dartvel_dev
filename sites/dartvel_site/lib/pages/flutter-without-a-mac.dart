import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Flutter without a Mac',
  description: 'Flutter without a Mac: what you can build, run and ship from '
      'a Windows or Linux machine today, and the three honest routes to an '
      'iOS build when you do not own one.',
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
                'whole of the restriction, and it is narrower than it sounds: '
                'everything else needs no Apple hardware at all. Writing the '
                'app, running it on a real iPhone, the website, Android, '
                'desktop, TVs, the backend, the database and the admin are '
                'all the same on Windows and Linux.'),
            Bullets(<String>[
              'On Windows or Linux today: dartvel dev, dartvel build web, '
                  'web-server, android, linux, windows, tizen, webos, '
                  'sony-elinux and vscode.',
              'The Mac is needed for exactly two commands: dartvel build ios '
                  'and dartvel build macos (and tvos, which is an Apple '
                  'target too).',
              'You can still test on an iPhone without one. See below.',
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
                <String>['Write the app, hot reload, dartvel dev', 'No'],
                <String>['Run it on a real iPhone over the pairing QR code', 'No'],
                <String>['dartvel build web and web-server', 'No'],
                <String>['dartvel build android, and ship to Google Play', 'No'],
                <String>['dartvel build windows, linux, and the TV targets', 'No'],
                <String>['Backend, database, auth, queues, Studio', 'No'],
                <String>['dartvel build ios, macos, tvos', 'Yes, Xcode'],
                <String>['Signing an IPA, and App Store submission', 'Yes, Xcode'],
              ],
            ),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('TEST ON AN IPHONE'),
            Heading('dartvel dev pairs a phone, and that includes an iPhone.'),
            Body('dartvel dev serves your app and prints a QR code. Scanning '
                'it from an iPhone opens the app the development server is '
                'running. No Apple developer account, no signing, no '
                'provisioning profile, and no Mac. It is not a store build, '
                'so it is not how you ship; it is how you see your work on '
                'the device while you build it.'),
            CodeBlock(<String>[
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
              'dartvel build ios --cloud. The build runs on our macOS '
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
              'Dartvel does not compile iOS on Linux. Nothing does, legally '
                  'or reliably, and a framework that claimed otherwise would '
                  'be lying to you.',
              'Dartvel Cloud is not open. Until it is, the macOS step is a '
                  'runner you configure or a Mac you rent.',
              'An App Store submission needs an Apple Developer account '
                  '(currently 99 USD a year), whoever owns the hardware.',
            ]),
            Objection(
              'So why is this better than plain Flutter?',
              'Plain Flutter has the same Apple restriction and none of the '
                  'rest: no pairing QR code, no backend, no admin, no store '
                  'submission command, no over-the-air patches, and no TV or '
                  'embedded targets. The Mac question is the same; everything '
                  'around it is not.',
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
