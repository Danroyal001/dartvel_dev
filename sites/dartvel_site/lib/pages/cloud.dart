import 'package:flutter/material.dart';
import '../components/docs.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel Cloud and Studio Pro', showAppBar: false)
@pragma('vm:entry-point')
Widget _cloudPage(BuildContext context) => DocsAnchors(
  // The CLI sends an account with no plan to #plans.
  ids: const <String>['plans'],
  builder: (BuildContext inner, Map<String, GlobalKey> keys) => ScrollToFragment(
    child: SingleChildScrollView(
      child: DVBox.list(<Widget>[
        const Section(
          glow: true,
          children: <Widget>[
            Eyebrow('DARTVEL CLOUD'),
            Heading(
              'Build for Android, iOS, Apple TV, Samsung TVs, Linux devices and browser extensions from any computer.',
              level: 1,
            ),
            Bullets(<String>[
              'Add --cloud to dartvel build. The build runs on our machines and its '
                  'log streams to your terminal.',
              'The output downloads into build/cloud and is checked against its '
                  'SHA-256 before it is kept.',
              'Cloud is not open yet. Every cloud build will be on a paid plan.',
            ]),
            CodeBlock(<String>[
              'export DARTVEL_CLOUD_TOKEN=...',
              '# a signed TPK, no Tizen Studio here',
              'dartvel build tizen --cloud',
              '# on a macOS worker',
              'dartvel build tvos --cloud --simulator',
              '# the extension and its web build',
              'dartvel build vscode --cloud',
              '# on a macOS worker',
              'dartvel build ios --cloud',
            ]),
          ],
        ),
        const Section(
          children: <Widget>[
            Eyebrow('SUBMIT'),
            Heading('Build and upload to Google Play or the App Store in one step.'),
            Bullets(<String>[
              'Google Play gets an App Bundle, and the App Store a signed IPA.',
              'Your iOS build is signed on a Mac with the certificate you keep in '
                  'Cloud.',
            ]),
            CodeBlock(<String>[
              'dartvel deploy --store play --cloud',
              'dartvel deploy --cloud \\',
              '  --store testflight',
              '# the same IPA on your own Mac, free',
              'dartvel build ios --format ipa',
            ]),
          ],
        ),
        const Section(
          tint: true,
          children: <Widget>[
            Eyebrow('UPDATES'),
            Heading('Push a fix to phones without waiting for store review.'),
            Bullets(<String>[
              'Cloud serves your patches, and devices check for them without a '
                  'token.',
              'You can also serve patches from your own web-server binary, for '
                  'free.',
            ]),
            CodeBlock(<String>[
              'export DARTVEL_UPDATES_TOKEN=\\',
              '\$DARTVEL_CLOUD_TOKEN',
              'src=https://cloud.dartvel.dev/updates',
              'dartvel updates patch \\',
              '  --patch-source \$src/<account>/<app>',
            ]),
          ],
        ),
        const Section(
          children: <Widget>[
            Eyebrow('CREDENTIALS'),
            Heading('Keep your keystore and signing keys off your laptop.'),
            Bullets(<String>[
              'Each key is sealed for one app, and only the machine building that '
                  'app opens it.',
              'Passwords go in through standard input, so they stay out of your '
                  'shell history.',
            ]),
            CodeBlock(<String>[
              'dartvel key cloud \\',
              '  android-keystore upload.jks',
              'printf %s "\$KEYSTORE_PASSWORD" |',
              '  dartvel key cloud \\',
              '  android-keystore-password -',
              '# lists what is kept, never values',
              'dartvel key cloud',
            ]),
          ],
        ),
        const Section(
          tint: true,
          children: <Widget>[
            Eyebrow('INTERNAL DISTRIBUTION'),
            Heading('Send testers a link and a QR code.'),
            Bullets(<String>[
              'A development build prints an install page and a QR code your '
                  'tester scans.',
              'Android installs this way. iOS test installs need signed builds '
                  'first.',
            ]),
            CodeBlock(<String>[
              'dartvel build android --cloud \\',
              '  --profile development',
            ]),
          ],
        ),
        const Section(
          children: <Widget>[
            Eyebrow('HOSTING'),
            Heading('Run your web-server binary on Cloud.'),
            Bullets(<String>[
              'Today you run that one file on your own server for free, with SQLite '
                  'created beside it.',
            ]),
            CodeBlock(<String>[
              '# one binary: web app, admin Studio,',
              '# SQLite on first run',
              'dartvel build web-server',
            ]),
          ],
        ),
        const Section(
          tint: true,
          children: <Widget>[
            Eyebrow('WORKFLOWS'),
            Heading('Chain the build and the upload in one run.'),
            Bullets(<String>[
              'A cloud build publishes when it succeeds.',
              'Runs on every push are planned.',
            ]),
            CodeBlock(<String>[
              '# the worker prints the upload',
              'dartvel deploy --cloud --dry-run \\',
              '  --store firebase-app-distribution',
            ]),
          ],
        ),
        const Section(
          children: <Widget>[
            Eyebrow('WHERE IT STANDS'),
            Heading('What exists today and what is still planned.'),
            DVBox.wrapLine(<Widget>[
              SiteCard(
                'The --cloud options',
                'dartvel build, deploy and key cloud pack your app, follow the '
                    'log and download the result.',
                built: true,
              ),
              SiteCard(
                'Ten targets built end to end',
                'Android, Fire OS, iOS, Apple TV, Tizen, Sony eLinux, terminal apps, '
                    'and Chrome, Firefox and VS Code extensions, each built by a '
                    'worker in our CI and checked when it came back.',
                built: true,
              ),
              SiteCard(
                'macOS, Windows, Linux and web on Cloud',
                'Cloud takes these builds. Our CI has not built them end to end yet.',
                built: false,
              ),
              SiteCard(
                'Hosted build machines',
                'The service and its workers are written and run in our CI. No '
                    'machines take customer builds yet.',
                built: false,
              ),
              SiteCard(
                'Managed iOS signing',
                'Certificates and profiles issued from your App Store Connect key, '
                    'tested against a stand-in for Apple.',
                built: false,
              ),
              SiteCard(
                'Store upload from Cloud',
                'The App Bundle and the IPA build today. The upload from our '
                    'machines waits on them.',
                built: false,
              ),
              SiteCard(
                'OTA patches on Cloud',
                'A patch source for each app, with your Cloud token to publish.',
                built: false,
              ),
              SiteCard(
                'Hosting and a dashboard',
                'Your web-server binary on a domain, and one place to see builds, '
                    'releases and crashes.',
                built: false,
              ),
            ], spacing: 16),
          ],
        ),
        const Section(
          tint: true,
          children: <Widget>[
            Eyebrow('STUDIO PRO'),
            Heading('Studio Pro adds a visual workflow builder to Studio.'),
            Bullets(<String>[
              'Build a backend function from steps and export it as an ordinary '
                  '@DVBackendFunction. Figma import, revision history and team '
                  'approval come with it.',
            ]),
            GhostLink('See Studio and Studio Pro', '/studio'),
          ],
        ),
        KeyedSubtree(
          key: keys['plans'],
          child: const Section(
            children: <Widget>[
              Eyebrow('PLANS'),
              Heading('Cloud builds are paid only.'),
              Bullets(<String>[
                'There is no free tier for cloud builds.',
                'Plans open when the hosted service launches.',
              ]),
            ],
          ),
        ),
        const Section(
          tint: true,
          children: <Widget>[
            Eyebrow('TODAY'),
            Heading('Build, deploy and patch from your own machine for free.'),
            CodeBlock(<String>[
              'dartvel build android',
              'dartvel deploy \\',
              '  --store firebase-app-distribution',
              'src=https://example.com/updates',
              'dartvel updates patch \\',
              '  --patch-source \$src',
            ]),
            Objection(
              'Will I need Cloud to ship my app?',
              'No. Local builds, store uploads, OTA from your own binary and '
                  'hosting your app yourself stay free, and Cloud never gates them.',
            ),
            DVBox.wrapLine(<Widget>[
              PrimaryLink('Create your first app', '/docs'),
              GhostLink('See what works today', '/features'),
            ], spacing: 12),
          ],
        ),
        const SiteFooter(),
      ], spacing: 0),
    ),
  ),
);
