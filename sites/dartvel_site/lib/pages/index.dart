import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

@DVPage(
  title: 'Dartvel: the AI-native, full-stack platform for Flutter',
  description: 'Dartvel is the AI-native, full-stack platform for Flutter: '
      'pages, data models and backend functions in one Dart project, with AI, '
      'sign-in, a database, jobs and an admin, built for phones, desktops, the '
      'web and TVs.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const SingleChildScrollView(
      // A scroll, like every other page on the site. This was a deck: one
      // section per flick, snapped by PageScrollPhysics, with a wheel handler
      // holding a cooldown. On a phone that is a page that fights the finger --
      // a short drag springs back, a long one jumps a whole section, and the
      // bottom of one section and the top of the next can never be on screen
      // together, which on a narrow screen is most of reading.
      //
      // The order is the argument: what it is and a piece of it working, where
      // it runs, what you write, and then proof that it runs today.
      child: DVBox.list(<Widget>[
        HeroSection(),
        OneProject(),
        Proof(),
        BackendProof(),
        OneFileBackend(),
        StudioProof(),
        PhoneLoop(),
        OtaUpdates(),
        RoutingProof(),
        Targets(),
        RunningOnDartvel(),
        ExpoComparison(),
        Honest(),
        StartNow(),
        SiteFooter(),
      ], spacing: 0),
    );

/// The first screen: what Dartvel is, and a piece of it running.
///
/// The colour drifting behind it is the framework's meshGradient, held still
/// for a reader who has asked for less motion. The band does not fade in:
/// the first screen is the one thing a visitor should never wait for.
@DVFunctionalWidget()
Widget _heroSection(BuildContext context) => Section(
      mesh: Palette.of(context).heroMesh,
      reveal: false,
      children: <Widget>[
        context.screen.isMobile
            ? const DVBox.list(<Widget>[HeroCopy(), HeroDemo()], spacing: 32)
            : const DVBox.row(<Widget>[
                Expanded(flex: 6, child: HeroCopy()),
                Expanded(flex: 5, child: HeroDemo()),
              ], spacing: 48, crossAlign: .start),
      ],
    );

/// The banner, written for the reader who sees nothing else.
///
/// It names the whole platform, then what you write and what Dartvel does
/// with it, then the parts that are Shipped in docs/spec-status.json as
/// links. The version is kDartvelVersion, which the release tooling moves:
/// a version typed into this sentence said 0.11.5 through two releases.
@DVFunctionalWidget()
Widget _heroCopy(BuildContext context) => DVBox.list(<Widget>[
  // The title block is tight and the gap after it is the largest in the
  // hero, which is the hierarchy a skimming reader is looking for.
  DVBox.list(<Widget>[
    const Eyebrow('FLUTTER\'S LARAVEL'),
    const DVText('The AI-native, full-stack platform for Flutter.')
        .modifier(
      const DVModifier()
          .fontSize(context.screen.value<double>(mobile: 30, desktop: 50))
          .fontWeight(.w700)
          .color(Palette.of(context).ink)
          .lineHeight(1.08)
          // The site's one h1.
          .semanticHeading(1),
    ),
    const DVText(
      'You write pages, data models and backend functions. Dartvel generates '
      'the routes, forms, typed client and API server, and builds the app for '
      'the web, phones, desktops and TVs.',
    ).modifier(
      const DVModifier()
          .fontSize(context.screen.value<double>(mobile: 17, desktop: 20))
          .fontWeight(.w500)
          .color(Palette.of(context).muted)
          .lineHeight(1.5)
          .maxWidth(580),
    ),
  ], spacing: 14),
  // Each one Shipped in docs/spec-status.json, and each a link to its docs.
  const DVBox.wrapLine(<Widget>[
    HeroCapability('AI built in', DVRoutes.docsai),
    HeroCapability('Sign-in and permissions', DVRoutes.docsauth),
    HeroCapability('Database and search', DVRoutes.docsdatabase),
    HeroCapability('Background jobs', DVRoutes.docsqueues),
    HeroCapability('Studio admin', DVRoutes.studio),
    HeroCapability('SEO and PWA', DVRoutes.docswebhosting),
    HeroCapability('One-file server', DVRoutes.docsdeploying),
  ], spacing: 8),
  const Objection(
    'Do I have to leave Flutter?',
    'No. Your pages are Flutter widgets, and `dartvel build` runs the Flutter '
        'SDK you already have.',
  ),
  const DVBox.wrapLine(<Widget>[
    PrimaryLink('Create your first app', DVRoutes.docs),
    GhostLink('See what works today', DVRoutes.features),
  ], spacing: 12),
  DVText('FSL-1.1-MIT licensed. Dartvel $kDartvelVersion is on pub.dev.')
      .modifier(const DVModifier()
          .fontSize(14)
          .color(Palette.of(context).faint)
          .maxWidth(560)),
], spacing: 26);

/// One part of the platform, as a chip that opens its docs.
@DVFunctionalWidget()
Widget _heroCapability(BuildContext context, String label, DVRouteTarget to) =>
    DVNavLink(to: to, padding: .zero, child: SiteChip(label));

/// Where one project runs, each with the status the repository records.
///
/// A card that names a spec section takes its badge from the index, so it
/// cannot read Built for a section that is Partial. Mobile and desktop name
/// no section: their evidence is the verified rows in docs/build-targets.md.
/// Microcontrollers and XR headsets are paid targets, built by a private
/// package, and say so in their own words.
@DVFunctionalWidget()
Widget _oneProject(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('ONE PROJECT'),
    Heading('One Dart project, on every screen it needs to reach.'),
    DVBox.wrapLine(<Widget>[
      SiteCard(
        'Web',
        'Every page is rendered at build time with its title, description '
            'and readable text, then Flutter takes over in the browser.',
        section: 'Static Web Generation',
      ),
      SiteCard(
        'Web server',
        'One executable carries the backend, the web app and its database, '
            'and renders pages on request.',
        section: 'Deployment',
      ),
      SiteCard(
        'Phones',
        'Android and iOS builds from the same pages, with hot reload on a '
            'paired phone.',
        built: true,
      ),
      SiteCard(
        'Desktops',
        'Linux, macOS and Windows apps, each verified by building it and '
            'inspecting what came out.',
        built: true,
      ),
      SiteCard(
        'Microcontrollers',
        'With a Cloud plan, pages written only in DVBox, DVText and signals '
            'become firmware for boards like the ESP32-S3. Early.',
      ),
      SiteCard(
        'XR headsets',
        'With a Cloud plan, the same app opens as windows and volumes on '
            'visionOS and Horizon.',
        section: 'XR: Spatial Presentation',
      ),
      SiteCard(
        'Studio',
        'Edit pages and records in a browser, served by your own web-server '
            'binary.',
        section: 'Dartvel Studio',
        href: DVRoutes.studio,
      ),
    ], spacing: 16),
  ],
);

@DVFunctionalWidget()
Widget _proof(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('DATA MODELS'),
    Heading('Write one class. Get its form, table, admin and typed client.'),
    CodeBlock(<String>[
      "@DVModel(subject: DVSubject.field('authorId'))",
      'class const _Article({',
      '  required final String slug,',
      '  @DVModel.pageTitle() required final String title,',
      '  @DVModel.mainContent() required final String body,',
      '  required final String authorId,',
      '  @DVModel.sensitiveField() required final String authorEmail,',
      '});',
    ]),
    Bullets(<String>[
      '`dartvel dev` regenerates the form, table, admin and typed client '
          'each time you save the class.',
      'Article.Form() is a form that creates an article, and article.Form() '
          'one that edits it. Saving checks the rules each field declares.',
      'authorEmail stays out of logs, search, public JSON and the admin until '
          'a policy allows it, and erasing an author reaches it through authorId.',
    ]),
    DVBox.wrapLine(<Widget>[
      SiteChip('Article.Form()'),
      SiteChip('Article.Page.fromId(...)'),
      SiteChip('Article.Table(...)'),
      SiteChip('Article.Admin()'),
    ], spacing: 8),
  ],
);

@DVFunctionalWidget()
Widget _backendProof(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('BACKEND FUNCTIONS'),
    Heading('Call your server like a local Dart function.'),
    CodeBlock(<String>[
      '// Server: lib/backend/functions/hello.get.dart',
      '@DVBackendFunction()',
      "Future<String> _hello(String name) async => 'Hello, \$name';",
      '',
      '// Client: the same types, checked by the compiler',
      "final String greeting = await hello(name: 'Ada');",
    ]),
    Bullets(<String>[
      'The HTTP endpoint and its typed client are generated together, so '
          'there is no JSON to write on either side.',
      'Return a Stream and the function is served as server-sent events.',
      'A Rust server built on Axum and Tokio calls your Dart through FFI.',
    ]),
    UpstreamCredits(
      ids: <String>['axum', 'tokio'],
      lead: 'Thanks to the Rust projects the server is built on:',
    ),
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
          'dartvel.admin.enabled, grant yourself access with '
          '`dartvel admin grant`, and open it at /__studio. '
          'Your backend stays in Dart beside your Flutter app, with a typed '
          'client generated for it.',
    ),
    DVBox.wrapLine(<Widget>[
      PrimaryLink('Build your one-file backend', DVRoutes.docsdeploying),
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
      'Frontend and backend functions are built from steps, free. Studio Pro, '
          'with Dartvel Cloud, adds Figma import and team review.',
    ]),
    StudioShot(
      'assets/studio_shots/page-builder.png',
      'Dartvel Studio page builder with the Layers tree, a selected heading '
          'on the canvas and the inspector',
    ),
    DVBox.wrapLine(<Widget>[GhostLink('See Studio and Studio Pro', DVRoutes.studio)]),
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
      'Or run in Dartvel Preview to test any project instantly without '
          'building it for the device first.',
    ]),
    Objection(
      'Does it work on an iPhone?',
      'Yes, with one limit. CI pairs an iOS simulator, an Android emulator '
          'and Linux, macOS and Windows desktops, edits a file and checks the '
          'change runs. On a '
          'physical iPhone a debug build only starts from Xcode or '
          '`flutter run`, so launch it from there and it pairs. Dartvel '
          'Preview runs on Android and desktops and is not on an iPhone yet.',
    ),
    DVBox.wrapLine(<Widget>[
      GhostLink('See Dev Client and Preview', DVRoutes.docsdevclient),
    ]),
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
    UpstreamCredit('shorebird', lead: 'DV.Updates runs on the'),
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
          'Dartvel\'s router with DVGoRoutes. Or keep your router: go_router, '
          'auto_route, Navigator 1.0 or 2.0, or a RouterConfig of your own.',
    ),
    DVBox.wrapLine(<Widget>[GhostLink('Read the routing docs', DVRoutes.docsrouting)]),
  ],
);

@DVFunctionalWidget()
Widget _targets(BuildContext context) => Section(
  // The one band that stops the scroll.
  dark: true,
  children: <Widget>[
    const Eyebrow('BUILD TARGETS', onDark: true),
    const Heading('Eleven targets build today.', onDark: true),
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
      ])
        SiteChip(target, onDark: true),
    ], spacing: 8),
    const Eyebrow('WITH A DARTVEL CLOUD PLAN', onDark: true),
    DVBox.wrapLine(<Widget>[
      for (final String target in const <String>[
        'visionos',
        'horizon',
        'chrome-extension',
        'firefox-extension',
        'vscode',
        'telegram',
        'linux-cli',
      ])
        SiteChip(target, onDark: true),
    ], spacing: 8),
    const Bullets(onDark: true, <String>[
      'Verified means the build ran and its output was inspected.',
      'webOS is in progress.',
    ]),
    const UpstreamCredits(
      onDark: true,
      ids: <String>[
        'tvos', 'tizen', 'elinux', 'webos',
      ],
    ),
    const Stats(onDark: true, <Figure>[
      Figure('11', 'targets that build'),
      Figure('1', 'target in progress'),
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
        '`dartvel build <target> --profile development`, paired with '
            '`dartvel dev` by a QR code. CI pairs Android, the iOS simulator and '
            'the Linux, macOS and Windows desktops.',
      ),
      SiteCard(
        'Over-the-air updates',
        '`dartvel updates patch --patch-source` publishes into your own '
            'web-server binary. Proven on an Android emulator in CI; iOS is '
            'not supported yet, where EAS Update covers both.',
      ),
      SiteCard(
        'Cloud builds',
        'Dartvel Cloud builds are coming and not open yet. Today you build '
            'on your own machine or in CI.',
        href: DVRoutes.cloud,
      ),
    ], spacing: 16),
  ],
);

@DVFunctionalWidget()
Widget _honest(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('STATUS'),
    Heading('$kSpecShipped spec sections ship today.'),
    DVBox.wrapLine(<Widget>[
      Stat('$kSpecShipped', 'sections shipped'),
      Stat('$kSpecPartial', 'sections partial'),
      Stat(kDartvelVersion, 'current version'),
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
      PrimaryLink('Check what works today', DVRoutes.features),
      ExternalLink('Read spec-status.json', kSpecStatusUrl),
    ], spacing: 20, crossAlign: .center),
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
          'under the Functional Source License: you can fork it for anything '
          'except a competing product, and each release becomes MIT two '
          'years after it ships.',
    ),
    // In a row, as the other buttons are: directly in the section's column
    // it stretched to the full width of the page.
    DVBox.wrapLine(<Widget>[PrimaryLink('Create your first app', DVRoutes.docs)]),
  ],
);

/// Proof from what this project runs itself, with only measured numbers.
///
/// The site you are reading is a Dartvel app served by the binary
/// `dartvel build web-server` writes, with its search backend and Studio in
/// the same file. Both figures are from docs/web-performance.md, measured
/// with Lighthouse on https://dartvel.dev, and test/home_alive_test.dart
/// fails if either is not there.
@DVFunctionalWidget()
Widget _runningOnDartvel(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('RUNNING ON DARTVEL'),
    Heading('This site is a Dartvel app, served by one Dartvel binary.'),
    DVBox.wrapLine(<Widget>[
      SiteCard(
        'dartvel.dev',
        'Every page here is a @DVPage, rendered on request by the web-server '
            'binary with its head, meta tags and crawler text.',
        built: true,
      ),
      SiteCard(
        'Search',
        'Ctrl+K asks a backend function in the same binary, which ranks '
            'every page of these docs.',
        built: true,
        href: DVRoutes.docssearch,
      ),
      SiteCard(
        'Studio',
        'The same file serves the Studio this site is edited in, open only '
            'to an account granted Studio.access.',
        built: true,
        href: DVRoutes.studio,
      ),
    ], spacing: 16),
    Stats(<Figure>[
      Figure('16 ms', 'to the first byte, phone profile'),
      Figure('7 KB', 'of compressed HTML per page'),
    ]),
    Body('Measured with Lighthouse on 28 September 2026. The full table, and '
        'what is still slow, is in docs/web-performance.md.'),
  ],
);
