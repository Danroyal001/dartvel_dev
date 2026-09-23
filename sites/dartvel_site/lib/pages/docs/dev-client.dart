import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Run a Dartvel app on your phone with dartvel dev',
  description: 'Scan a QR code and your phone runs the code on your laptop. '
      'Every save hot reloads over the network, with no cable and no '
      'rebuild.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsDevClientPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsdevclient,
      lead: <String>[
        'Scan a QR code and your phone runs the code on your laptop.',
        'Every save hot reloads the phone over the network, with no cable.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'build',
          title: 'Build a development app once',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel build android --profile development',
              'dartvel build ios --simulator --profile development',
              'dartvel build macos --profile development',
              'dartvel build linux --profile development',
              'dartvel build windows --profile development',
            ]),
            Bullets(<String>[
              'A development build is a Flutter debug build with a pairing '
                  'tunnel added to it.',
              'A profile or release build takes the tunnel back out, so it never '
                  'ships in your app.',
              'Install it the usual way. You rebuild it only when your native '
                  'plugins change.',
            ]),
          ],
        ),
        DocsSection(
          id: 'pair',
          title: 'Pair it with dartvel dev',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel dev',
              'dartvel dev --pairing-port 8787',
            ]),
            Bullets(<String>[
              'dartvel dev always serves pairing and prints a QR code. There is '
                  'no flag to turn it on.',
              'Scan the code with the phone, or pass the printed link as a '
                  'launch argument on a desktop or simulator.',
              'Pairing hot restarts the app onto your current code. After that, '
                  'each save is a hot reload.',
            ]),
            DocsText('With no device plugged in, dartvel dev keeps running and '
                'waits for paired devices.'),
          ],
        ),
        DocsSection(
          id: 'security',
          title: 'Who can connect',
          children: <Widget>[
            Bullets(<String>[
              'Each run makes a new key and token, and the QR code carries both.',
              'The connection is TLS, and the app checks that the server holds '
                  'the key from the code before it sends the token.',
              'A request without the token gets 401.',
            ]),
          ],
        ),
        DocsSection(
          id: 'stores',
          title: 'Keep development builds out of the stores',
          children: <Widget>[
            DocsText('dartvel deploy --store recognises a development build '
                'and refuses it for Play alpha, beta and production and for the '
                'App Store, with DV-DEVCLIENT-003.'),
            DocsText('Play internal testing, TestFlight and Firebase App '
                'Distribution accept one, so testers can pair too.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Dev Client', missing: <String>[
              'CI pairs Android, iOS simulator, macOS, Linux and Windows builds. '
                  'A physical iPhone pairs when you start the app from Xcode or '
                  'flutter run.',
              'TV and embedded targets have no development build.',
              'A development build cannot connect to a preview environment.',
            ]),
          ],
        ),
      ],
    );
