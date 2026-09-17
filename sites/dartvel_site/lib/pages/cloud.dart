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
              'Build for iOS, macOS, Windows, Linux, Android and the web from any computer.',
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
              'dartvel build ios --cloud          # on a macOS worker',
              'dartvel build windows --cloud      # on a Windows worker',
              'dartvel build web-server --cloud   # on a Linux worker',
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
              'dartvel deploy --store testflight --cloud',
              'dartvel build ios --format ipa   # the same IPA on your own Mac, for free',
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
              'DARTVEL_UPDATES_TOKEN=\$DARTVEL_CLOUD_TOKEN \\',
              '  dartvel updates patch --patch-source https://cloud.dartvel.dev/updates/<account>/<app>',
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
              'dartvel key cloud android-keystore upload.jks',
              'printf %s "\$KEYSTORE_PASSWORD" | dartvel key cloud android-keystore-password -',
              'dartvel key cloud   # lists what is kept, never the values',
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
              'dartvel build android --cloud --profile development',
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
              'dartvel build web-server   # one binary: web app, admin Studio, SQLite on first run',
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
              'dartvel deploy --store firebase-app-distribution --cloud --dry-run   # the worker prints the upload',
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
                'dartvel build, publish and key cloud pack your app, follow the '
                    'log and download the result.',
                built: true,
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
            Heading('Import a Figma file as pages you can edit and export.'),
            Bullets(<String>[
              'Every top-level frame becomes a page in the builder.',
              'Export each page as an ordinary @DVPage file in your repository.',
              'Pro lives in the private dartvel_enterprise repository.',
            ]),
            DVBox.wrapLine(<Widget>[
              SiteCard(
                'Figma import',
                'Auto-layout, type, shadows, gradients and icons come through. '
                    'Images are downloaded, so they survive Figma\'s expiring URLs.',
                built: true,
              ),
              SiteCard(
                'Reusable components',
                'Save a node as a component and push a change to every instance '
                    'on every page.',
                built: true,
              ),
              SiteCard(
                'Revision history',
                'Every save is numbered and attributed. Restore any of them in one '
                    'tap.',
                built: true,
              ),
              SiteCard(
                'Multi-user editing and approval',
                'See each other\'s edits live. An approver signs off before a page '
                    'goes live.',
                built: true,
              ),
              SiteCard(
                'Workflow builder',
                'Compose a backend function visually and export it as a plain '
                    '@DVBackendFunction.',
                built: true,
              ),
              SiteCard(
                'Enterprise SSO',
                'SAML, SCIM provisioning and directory sync for your team.',
                built: false,
              ),
            ], spacing: 16),
            Objection(
              'Do I need Pro to build pages visually?',
              'No. The builder with drag and drop, undo and code export is free.',
            ),
            GhostLink('See what the free Studio does', '/features'),
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
            Heading('Build, publish and patch from your own machine for free.'),
            CodeBlock(<String>[
              'dartvel build android --profile release',
              'dartvel deploy --store firebase-app-distribution',
              'dartvel updates patch --patch-source https://your-server.example/updates',
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
