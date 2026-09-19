import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

@DVPage(title: 'Dartvel: a Flutter app and its backend in one Dart project', showAppBar: false)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const SingleChildScrollView(
      // A scroll, like every other page on the site. This was a deck: one
      // section per flick, snapped by PageScrollPhysics, with a wheel handler
      // holding a cooldown. On a phone that is a page that fights the finger --
      // a short drag springs back, a long one jumps a whole section, and the
      // bottom of one section and the top of the next can never be on screen
      // together, which on a narrow screen is most of reading.
      //
      // Every section below backs the headline: one Dart project for the app
      // and its backend. Anything that did not was cut.
      child: DVBox.list(<Widget>[
        HeroSection(),
        Proof(),
        BackendProof(),
        OneFileBackend(),
        StudioProof(),
        PhoneLoop(),
        OtaUpdates(),
        RoutingProof(),
        Targets(),
        ExpoComparison(),
        Honest(),
        StartNow(),
        SiteFooter(),
      ], spacing: 0),
    );

@DVFunctionalWidget()
Widget _heroSection(BuildContext context) {
  final bool narrow = context.screen.isMobile;
  const Widget copy = HeroCopy();
  return Section(
    glow: true,
    children: <Widget>[
      // Two columns where there is room. On a phone the terminal follows the
      // buttons, so the proof is still the next thing a thumb reaches.
      if (narrow) ...const <Widget>[copy, HeroTerminal()]
      else
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 6, child: copy),
            SizedBox(width: 48),
            Expanded(flex: 5, child: HeroTerminal()),
          ],
        ),
    ],
  );
}

@DVFunctionalWidget()
Widget _heroCopy(BuildContext context) => DVBox.list(<Widget>[
  // The title block is tight and the gap after it is the largest in the
  // hero, which is the hierarchy a skimming reader is looking for.
  DVBox.list(<Widget>[
    const Eyebrow('FLUTTER\'S LARAVEL'),
    const DVText('Ship a Flutter app and its backend from one Dart project.')
        .modifier(
      const DVModifier()
          .fontSize(context.screen.value<double>(mobile: 34, desktop: 50))
          .fontWeight(FontWeight.w800)
          .color(Palette.of(context).ink)
          .lineHeight(1.08)
          // The site's one h1.
          .semanticHeading(1),
    ),
    const DVText(
      'Write a model and a function. Dartvel generates the routes, forms, typed '
      'client and API server, then builds them into one file for your server.',
    ).modifier(
      const DVModifier()
          .fontSize(context.screen.value<double>(mobile: 17, desktop: 20))
          .fontWeight(FontWeight.w500)
          .color(Palette.of(context).muted)
          .lineHeight(1.5)
          .maxWidth(580),
    ),
  ], spacing: 14),
  const Objection(
    'Do I have to leave Flutter?',
    'No. Your pages are Flutter widgets, and dartvel build runs the Flutter '
        'SDK you already have.',
  ),
  const DVBox.wrapLine(<Widget>[
    PrimaryLink('Create your first app', '/docs'),
    GhostLink('See what works today', '/features'),
  ], spacing: 12),
  const DVText('MIT licensed. dartvel_dev 0.5.0 is on pub.dev.').modifier(
    const DVModifier()
        .fontSize(14)
        .color(Palette.of(context).faint)
        .maxWidth(560),
  ),
], spacing: 26);

/// A terminal beside the hero, so the promise sits next to what you type.
///
/// Every line after the commands is a line the CLI prints: the dev loop's
/// start, the generated backend announcing its port, and the loop reacting
/// to an edit. There is no timing on it, because nothing measured one.
class HeroTerminal extends StatelessWidget {
  const HeroTerminal();

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.rule),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.dark ? 0.5 : 0.14),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1B2338))),
            ),
            child: Row(
              children: <Widget>[
                for (final Color light in <Color>[
                  const Color(0xFFFF5F57),
                  const Color(0xFFFEBC2E),
                  const Color(0xFF28C840),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: light,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                const Text(
                  'dartvel dev',
                  style: TextStyle(
                    color: Color(0xFF8A95AD),
                    fontFamily: 'RobotoMono',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 18),
            // Coloured the way the terminal actually is: the prompt, what you
            // type and what it answers are three different things.
            child: Typewriter(
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontFamilyFallback: <String>['Menlo', 'Consolas', 'monospace'],
                fontSize: 12.5,
                height: 1.75,
                color: Color(0xFFD7E1F5),
              ),
              <TextSpan>[
                TextSpan(
                  text: '\$ ',
                  style: TextStyle(color: Color(0xFF9ECE6A)),
                ),
                TextSpan(text: 'dartvel create shop\n'),
                TextSpan(
                  text: '\$ ',
                  style: TextStyle(color: Color(0xFF9ECE6A)),
                ),
                TextSpan(text: 'cd shop && dartvel dev\n\n'),
                TextSpan(
                  text: 'dartvel dev: starting backend and Flutter app...\n',
                  style: TextStyle(color: Color(0xFF7080A8)),
                ),
                TextSpan(
                  text: '[backend] ',
                  style: TextStyle(color: Color(0xFF7080A8)),
                ),
                TextSpan(text: 'dartvel backend listening on '),
                TextSpan(
                  text: 'http://0.0.0.0:3000/api\n\n',
                  style: TextStyle(color: Color(0xFF7DCFFF)),
                ),
                TextSpan(
                  text: '# you save lib/backend/functions/get_post.dart\n',
                  style: TextStyle(color: Color(0xFF7080A8)),
                ),
                TextSpan(text: '[dev] regenerating...\n'),
                TextSpan(
                  text: '[dev] restarting backend...',
                  style: TextStyle(
                    color: Color(0xFF9ECE6A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

@DVFunctionalWidget()
Widget _proof(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('MODELS'),
    Heading('Write one class. Get its form, table, admin and typed client.'),
    CodeBlock(<String>[
      '@DVModel(generatePublicPages: true)',
      'class _Post {',
      '  @DVModel.pageTitle()',
      '  late String title;',
      '',
      '  @DVModel.mainContent()',
      '  late String body;',
      '',
      '  @DVModel.sensitiveField()',
      '  late String authorEmail;',
      '}',
    ]),
    Bullets(<String>[
      'dartvel dev regenerates the form, table, admin and typed client '
          'each time you save the class.',
      'Post.Form(...) validates input against the fields you declared.',
      'authorEmail stays out of logs, search and the admin until a policy '
          'allows it.',
    ]),
    DVBox.wrapLine(<Widget>[
      SiteChip('Post.Form(...)'),
      SiteChip('Post.Page.fromId(...)'),
      SiteChip('Post.Table(...)'),
      SiteChip('Post.Admin()'),
    ], spacing: 8),
  ],
);

@DVFunctionalWidget()
Widget _backendProof(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('BACKEND FUNCTIONS'),
    Heading('Call your server like a local Dart function.'),
    CodeBlock(<String>[
      '// Server',
      '@DVBackendFunction()',
      'Future<Post?> _getPost(String id) => Post.find(id);',
      '',
      '// Client',
      'final Post? post = await getPost(id);',
    ]),
    Bullets(<String>[
      'The HTTP endpoint and its typed client are generated together.',
      'Return a Stream and the function is served as server-sent events.',
      'A Rust server built on Axum and Tokio calls your Dart through FFI.',
    ]),
  ],
);

/// The web-server build as a PocketBase-style deploy: one file, SQLite made
/// on the first run in dartvel_data beside the executable, the way PocketBase
/// keeps pb_data beside its own. Every line in the terminal is what the binary
/// printed when it was copied alone into a directory and started, shown at
/// the /srv path a server would keep it under. No size is given: the file grows
/// with the backend it carries.
@DVFunctionalWidget()
Widget _oneFileBackend(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('ONE-FILE BACKEND'),
    Heading('Ship your app and its database as one file.'),
    CodeBlock(<String>[
      r'$ dartvel build web-server',
      'build/server: the backend, the web app and the native server, in one '
          'file.',
      '',
      r'$ cd /srv/shop && ./server',
      'dartvel: no DATABASE_URL, creating SQLite database /srv/shop/dartvel_data/data.db',
      'dartvel: created table notes',
      'dartvel backend listening on http://0.0.0.0:3000/api',
    ]),
    Bullets(<String>[
      'Copy one file to your server and run it. The first run creates your '
          'tables.',
      'The database lives in dartvel_data next to the binary, so you back up '
          'one folder.',
      'The web app, the API, the admin and the pages rendered on request all '
          'come from that file.',
    ]),
    Objection(
      'Why not use PocketBase?',
      'PocketBase is also one file with its admin inside, and you extend it '
          'in Go or JavaScript. This binary carries its admin too: turn on '
          'dartvel.admin.enabled, grant yourself access with dartvel admin '
          'grant, and open it at /__studio. '
          'Your backend stays in Dart beside your Flutter app, with a typed '
          'client generated for it.',
    ),
    DVBox.wrapLine(<Widget>[
      PrimaryLink('Build your one-file backend', '/docs/deploying'),
    ]),
  ],
);

/// Studio, which the one-file backend above already carries at /__studio.
/// The screenshot is that binary's own Studio, and /studio says what is
/// free and what is Pro.
@DVFunctionalWidget()
Widget _studioProof(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('STUDIO'),
    Heading('Edit pages and records from a browser, on the server you '
        'already run.'),
    Bullets(<String>[
      'Studio is free and runs inside your web-server binary. Apps never '
          'carry it.',
      'Build a page visually, and export it as an ordinary @DVPage file.',
      'Studio Pro adds a workflow builder that turns steps into a '
          '@DVBackendFunction.',
    ]),
    StudioShot(
      'assets/studio/page-builder.png',
      'Dartvel Studio page builder with the Layers tree, a selected heading '
          'on the canvas and the inspector',
    ),
    DVBox.wrapLine(<Widget>[GhostLink('See Studio and Studio Pro', '/studio')]),
  ],
);

/// Expo Go's job, done by a build of your own app. The output lines are the
/// dev command's own (dev_command.dart), and the loop is what the Dev client
/// workflow runs on an Android emulator, an iOS simulator and a Linux desktop:
/// pair by the printed link, edit, and check the edit is on the device with
/// the process unchanged.
@DVFunctionalWidget()
Widget _phoneLoop(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('HOT RELOAD ON A PHONE'),
    Heading('Scan a QR code and hot reload on your phone.'),
    CodeBlock(<String>[
      r'$ dartvel build android --profile development',
      r'$ dartvel dev',
      '[dartvel] Pairing: serving main on port 8787.',
      '[dartvel] Scan with the camera on a device running a development build:',
      '# the QR code and its dartvel-dev://pair link print here',
    ]),
    Bullets(<String>[
      'Install the development build once. It is your own app, so every '
          'plugin you added is in it.',
      'Scan the code, and each save hot reloads every paired phone over your '
          'local network.',
      'No USB cable and no emulator. No store-approved Go app to wait for.',
    ]),
    Objection(
      'Does it work on an iPhone?',
      'Yes, with one limit. CI pairs an iOS simulator, an Android emulator '
          'and a Linux desktop, edits a file and checks the change runs. On a '
          'physical iPhone a debug build only starts from Xcode or flutter '
          'run, so launch it from there and it pairs.',
    ),
  ],
);

/// DV.Updates on Shorebird's updater, with the web-server binary as the patch
/// source. The proof is the OTA updates workflow: dartvel updates release and
/// patch with --patch-source into a running binary, and the relaunched app
/// running the patch, with no Shorebird account. The section is Partial in
/// spec-status because iOS is not supported, and says so.
@DVFunctionalWidget()
Widget _otaUpdates(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('OVER-THE-AIR UPDATES'),
    Heading('Push a Dart fix to installed apps without waiting for store '
        'review.'),
    CodeBlock(<String>[
      '# shorebird.yaml: base_url: https://shop.example.com/updates',
      r'$ dartvel updates release --platform android --patch-source https://shop.example.com/updates',
      '# fix the bug, then',
      r'$ dartvel updates patch --platform android --patch-source https://shop.example.com/updates',
    ]),
    Bullets(<String>[
      'Your web-server binary serves the patches, so you need no Shorebird '
          'account.',
      'DV.Updates.check(), apply() and rollback() let the app choose when a '
          'patch installs.',
      'Staged rollout, pinned versions and skipped versions are decided in '
          'one check.',
    ]),
    Objection(
      'Is it finished?',
      'On Android, yes: CI releases an app, patches it into a running '
          'web-server binary and relaunches it into the patch. iOS is not '
          'supported yet.',
    ),
  ],
);

/// File routes and config routes in one router, and the parts real apps ask
/// for: a stack per tab, deep-link files, and a way in from GoRouter. Each
/// line is in spec-status's Routing record and the dartvel_example tests.
@DVFunctionalWidget()
Widget _routingProof(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('ROUTING'),
    Heading('Get typed routes, tab stacks and deep links without rewriting '
        'your router.'),
    CodeBlock(<String>[
      '// lib/routes.dart, beside the pages in lib/pages',
      'final List<DVRouteNode> routes = <DVRouteNode>[',
      '  DVRoute(path: \'/settings\', builder: (context, state) =>',
      '      const SettingsScreen()),',
      '];',
      '',
      '// Or mount every Dartvel route into your own GoRouter',
      'GoRouter(routes: <RouteBase>[...yourRoutes, ...dartvelRoutes(at: \'/app\')]);',
    ]),
    Bullets(<String>[
      'A (tabs) folder keeps a stack per tab, and back pops inside the tab '
          'you are on.',
      'dartvel.deepLinks in pubspec.yaml writes assetlinks.json and '
          'apple-app-site-association for you.',
      'A redirect or a _guard.dart runs before the page shows, and an async '
          'check shows a pending view while it decides.',
    ]),
    Objection(
      'Do I have to move my screens into lib/pages?',
      'No. Declare them in lib/routes.dart, or mount your GoRoute list inside '
          'Dartvel\'s router with DVGoRoutes.',
    ),
    DVBox.wrapLine(<Widget>[GhostLink('Read the routing docs', '/docs/routing')]),
  ],
);

@DVFunctionalWidget()
Widget _targets(BuildContext context) => Section(
  // The one band that stops the scroll.
  dark: true,
  children: <Widget>[
    const Eyebrow('BUILD TARGETS', onDark: true),
    const Heading('Fourteen targets build today.', onDark: true),
    DVBox.wrapLine(<Widget>[
      // Named the way you type them after dartvel build, and checked against
      // docs/build-targets.md by platform_breadth_test.dart.
      for (final String target in const <String>[
        'web',
        'web-server',
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'fireos',
        'tvos',
        'tizen',
        'sony-elinux',
        'vscode',
        'chrome-extension',
        'firefox-extension',
      ])
        SiteChip(target, onDark: true),
    ], spacing: 8),
    const Bullets(onDark: true, <String>[
      'Verified means the build ran and its output was inspected.',
      'Terminal apps build for Linux. webOS, Fuchsia and terminal apps on macOS and '
          'Windows are in progress.',
    ]),
    const Stats(onDark: true, <Figure>[
      Figure('14', 'targets that build'),
      Figure('4', 'targets in progress'),
      Figure('6', 'packages on pub.dev'),
    ]),
    const ExternalLink('Check the build log for each target', kBuildTargetsUrl,
        onDark: true),
  ],
);

/// What an Expo developer looks for first, and where each one stands.
@DVFunctionalWidget()
Widget _expoComparison(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('COMING FROM EXPO'),
    Heading('Two of the three Expo services you rely on work today.'),
    DVBox.wrapLine(<Widget>[
      SiteCard(
        'Development builds',
        'dartvel build <target> --profile development, paired with dartvel '
            'dev by a QR code. CI pairs Android, the iOS simulator and Linux.',
      ),
      SiteCard(
        'Over-the-air updates',
        'dartvel updates patch --patch-source publishes into your own '
            'web-server binary. Proven on an Android emulator in CI.',
      ),
      SiteCard(
        'Cloud builds',
        'There is no hosted build service and no certificate management. '
            'You build on your own machine or in CI.',
      ),
    ], spacing: 16),
  ],
);

@DVFunctionalWidget()
Widget _honest(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('STATUS'),
    Heading('28 spec sections ship today.'),
    DVBox.wrapLine(<Widget>[
      Stat('28', 'sections shipped'),
      Stat('72', 'sections partial'),
      Stat('0.5.0', 'current version'),
    ], spacing: 14),
    Bullets(<String>[
      'Every partial section names what is missing.',
      'A CI check fails when a shipped section cites evidence that is gone.',
    ]),
    Objection(
      'Is it production-ready?',
      'Parts of it. Check the section you need before you depend on it.',
    ),
    DVBox.wrapLine(<Widget>[
      PrimaryLink('Check what works today', '/features'),
      ExternalLink('Read spec-status.json', kSpecStatusUrl),
    ], spacing: 20, crossAlign: DVCrossAlign.center),
  ],
);

@DVFunctionalWidget()
Widget _startNow(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('START'),
    Heading('Create an app in three commands.'),
    CodeBlock(<String>[
      'brew install Danroyal001/dartvel_dev/dartvel_dev',
      'dartvel create shop',
      'cd shop && dartvel dev',
    ]),
    Objection(
      'Will I be locked in?',
      'Your pages are Flutter widgets, your backend is a file on your own '
          'server, and your patches can come from your own host. Dartvel is '
          'MIT licensed, so you can fork it.',
    ),
    // In a row, as the other buttons are: directly in the section's column
    // it stretched to the full width of the page.
    DVBox.wrapLine(<Widget>[PrimaryLink('Create your first app', '/docs')]),
  ],
);
