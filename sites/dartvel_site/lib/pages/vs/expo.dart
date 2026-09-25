import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Expo for Flutter',
  description: 'Expo for Flutter: development builds paired by QR code, '
      'store uploads with dartvel deploy --store, and over-the-air patches '
      'for Android. How that compares with Expo, EAS and Expo Router API '
      'routes.',
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
          grain: true,
          children: <Widget>[
            Eyebrow('EXPO FOR FLUTTER'),
            Heading(
              'Expo for Flutter, and a backend framework beside it.',
              level: 1,
            ),
            Body('Expo is the reason React Native is pleasant to work in: one '
                "command to start, builds on somebody else's machines, store "
                'submission, updates that reach users without a review, and, '
                'through Expo Router, API routes and server functions that '
                'deploy to EAS Hosting. Flutter gives you `flutter run` and '
                "each platform's own release tooling, and stops there. "
                'Dartvel is that missing layer for Flutter, with a backend '
                'framework in the same language: data models, auth, queues, '
                'mail and an admin.'),
            Bullets(<String>[
              'Install a development build of your app once. After that, '
                  '`dartvel dev` prints a QR code; scan it and the app pairs and '
                  'hot reloads over your network.',
              '`dartvel build android`, ios, macos, windows, linux, tvos, '
                  'tizen, sony-elinux, vscode and more. --cloud sends the '
                  'build to Dartvel Cloud, which is not open yet.',
              '`dartvel deploy --store play`, appstore, testflight or '
                  'firebase-app-distribution hands the upload to that '
                  "store's own tool.",
              '`dartvel updates patch` sends a Dart fix to Android apps over '
                  'the air, from your own web-server binary. iOS is not '
                  'supported yet.',
            ]),
            CodeBlock(<String>[
              'dartvel build android --profile development',
              'dartvel dev            # QR code, pair, hot reload',
              'dartvel deploy --store play',
              'dartvel updates patch --platform android',
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
                <String>['Language', 'TypeScript or JavaScript, with React', 'Dart, front and back'],
                <String>['Run on a device', '`npx expo start`, with Expo Go or a development build', 'A development build, paired by `dartvel dev` over a QR code'],
                <String>['Cloud builds', 'EAS Build, with a free tier and paid plans', '`dartvel build --cloud`. Cloud is not open yet'],
                <String>['Local builds', '`npx expo run`, or eas build --local', '`dartvel build android`, ios, linux and the rest'],
                <String>['Store submission', 'EAS Submit', "`dartvel deploy --store`, through each store's own tool"],
                <String>['Over the air', 'EAS Update, on Android and iOS', '`dartvel updates`, Android only, from Shorebird or your own binary'],
                <String>['Server code', 'Expo Router API routes (+api.ts), server middleware, and React Server Functions in beta', '@DVBackendFunction, with a typed client generated from it'],
                <String>['Hosting the server', 'EAS Hosting, or most other hosts', 'One binary from `dartvel build web-server`, on a machine you run'],
                <String>['Database', 'expo-sqlite on the device. For a server database the docs point to Convex, Supabase or Firebase', 'Data models on SQLite, Postgres or MySQL, with migrations'],
                <String>['Auth', 'Guides for OAuth providers and auth SDKs, and redirects in Expo Router', 'Sessions, passkeys, SAML, LDAP and second factors, built in'],
                <String>['Admin', 'None built in', 'Studio, served by your own binary'],
                <String>['TVs', 'Android TV and Apple TV, through react-native-tvos', 'Android TV, Apple TV, Samsung Tizen'],
                <String>['Desktop and embedded', 'Not covered by the Expo docs', 'macOS, Windows, Linux, Sony embedded Linux'],
              ],
            ),
            UpstreamCredits(ids: <String>[
              'tizen', 'tvos', 'elinux', 'vscode',
            ]),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('THE BACKEND'),
            Heading('Both reach a server. They stop in different places.'),
            Body('An Expo Router API route is a file such as app/hello+api.ts '
                'that exports GET or POST handlers, and a React Server '
                'Function is called from a component like a typed function. '
                'Both deploy to EAS Hosting or another host, and a native '
                'build finds them through the origin set in the Expo Router '
                'config plugin, which Expo marks as alpha. What Expo leaves to '
                'you is what sits behind the handler: its database guide sends '
                'you to Convex, Supabase or Firebase, and sign-in comes from an '
                "auth SDK. Dartvel's backend is a framework of its own. A "
                'backend function is Dart, the client that calls it is '
                'generated from it, so renaming an argument breaks the build, '
                'and the models, auth, policies, queues and mail it uses come '
                'with it.'),
            CodeBlock(<String>[
              '@DVBackendFunction()',
              'Future<Invoice> _issue(String orderId) async { ... }',
              '',
              '// in the app, typed, generated, no fetch and no string URL',
              'final Invoice invoice = await issue(orderId: order.id);',
            ]),
            Bullets(<String>[
              'A data model generates its table, its migration, a typed '
                  'client, a form and an admin screen.',
              'Model change streams and an offline store are built. Carrying '
                  'a change from the server to a phone is not built yet, so a '
                  'list on one device does not update when another device '
                  'writes.',
              'One binary from `dartvel build web-server` runs the site, the '
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
              'EAS is running today, with a free tier and paid plans: Build, '
                  'Submit, Update, Hosting and Workflows. Dartvel Cloud is '
                  'built and not open, so --cloud needs a token nobody can buy '
                  'yet. Local builds, store uploads and Android patches from '
                  'your own binary are free and work now.',
              "EAS Update reaches iOS and Android. Dartvel's over-the-air "
                  'patches reach Android only.',
              'Expo Go runs a project on a phone with no build of your own. '
                  'Dartvel always needs a development build, and a physical '
                  'iPhone pairs only when the app is started from Xcode or '
                  '`flutter run`.',
              'eas deploy puts API routes on a hosted server in one command. '
                  "Dartvel's web-server binary runs on a machine you provide.",
              "Expo's ecosystem of config plugins and prebuilt modules is "
                  'years old and very large, and React Native has more people '
                  'to hire and more answers already written down.',
            ]),
            VersusFair('Expo is very good at what it does, and Dartvel copies '
                'the shape of it on purpose. Both reach the server now: Expo '
                'through API routes and server functions, Dartvel through a '
                'backend framework in the language the app is written in. If '
                'you want React and a hosted pipeline that works today, choose '
                'Expo. If you want Flutter, targets past the phone, and data '
                'models, auth and an admin in the same repository, that is '
                'what Dartvel is for.'),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Start an app', '/docs'),
              GhostLink('What ships today', '/features'),
              GhostLink('Build without a Mac', '/flutter-without-a-mac'),
            ], spacing: 12),
            VersusChecked('Expo', 'https://docs.expo.dev/llms.txt',
                '2026-09-25'),
          ],
        ),
        Section(children: <Widget>[VersusMore(current: '/vs/expo')]),
        SiteFooter(),
      ], spacing: 0),
    );
