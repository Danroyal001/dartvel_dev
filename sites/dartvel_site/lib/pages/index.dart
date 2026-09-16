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
        ImportApi(),
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
      'Annotate a class and a function. Dartvel generates the routes, forms, '
      'typed client and API server.',
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
    Heading('Write one class. Get its form, table and admin.'),
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
      'Post.Form(...) validates input against the fields you declared.',
      'Post.Table(...) and Post.Admin() list and edit rows with no extra code.',
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

@DVFunctionalWidget()
Widget _importApi(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('EXISTING APIS'),
    Heading('Already have an API? Import its spec.'),
    CodeBlock(<String>[
      'dartvel import openapi openapi.yaml',
      'dartvel import postman collection.json',
    ]),
    Bullets(<String>[
      'Each schema becomes a model under lib/models.',
      'Each operation becomes a typed function under lib/api.',
      'A field the spec does not require comes out nullable.',
    ]),
  ],
);

@DVFunctionalWidget()
Widget _targets(BuildContext context) => Section(
  // The one band that stops the scroll.
  dark: true,
  children: <Widget>[
    const Eyebrow('BUILD TARGETS', onDark: true),
    const Heading('Twelve targets build today.', onDark: true),
    DVBox.wrapLine(<Widget>[
      for (final String target in const <String>[
        'web',
        'android',
        'iOS',
        'macOS',
        'windows',
        'linux',
        'Fire OS',
        'tvOS',
        'Tizen',
        'VS Code',
        // The two extension targets, named the way you would type them. As
        // bare browser names they read as a third way to ship a web app.
        'chrome-extension',
        'firefox-extension',
      ])
        SiteChip(target, onDark: true),
    ], spacing: 8),
    const Bullets(onDark: true, <String>[
      'Verified means the build ran and its output was inspected.',
      'In progress: webOS, Sony eLinux, Fuchsia and terminal apps.',
    ]),
    const Stats(onDark: true, <Figure>[
      Figure('12', 'targets that build'),
      Figure('4', 'targets in progress'),
      Figure('6', 'packages on pub.dev'),
    ]),
    const ExternalLink('Check the build log for each target', kBuildTargetsUrl,
        onDark: true),
  ],
);

/// What "Flutter's Expo" covers, and the one part it does not.
@DVFunctionalWidget()
Widget _expoComparison(BuildContext context) => const Section(
  tint: true,
  children: <Widget>[
    Eyebrow('COMING FROM EXPO'),
    Heading('Dartvel covers two of the three jobs Expo does.'),
    DVBox.wrapLine(<Widget>[
      SiteCard(
        'The SDK',
        'Auth, notifications, storage, database, queues and AI are built in, '
            'as DV.Auth, DV.Notifications, DV.Storage, DV.Database, DV.Queues and DV.AI.',
      ),
      SiteCard(
        'Over-the-air updates',
        'dartvel updates release, patch and rollback drive Shorebird. '
            'The in-app DV.Updates call is still in progress.',
      ),
      SiteCard(
        'Cloud builds',
        'Missing. There is no hosted build service and no certificate '
            'management. You build on your own machine or CI.',
      ),
    ], spacing: 16),
  ],
);

@DVFunctionalWidget()
Widget _honest(BuildContext context) => const Section(
  children: <Widget>[
    Eyebrow('STATUS'),
    Heading('33 spec sections ship today.'),
    DVBox.wrapLine(<Widget>[
      Stat('33', 'sections shipped'),
      Stat('66', 'sections partial'),
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
    ], spacing: 20),
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
      'Your pages are Flutter widgets and your code stays in your repository. '
          'Dartvel is MIT licensed, so you can fork it.',
    ),
    // In a row, as the other buttons are: directly in the section's column
    // it stretched to the full width of the page.
    DVBox.wrapLine(<Widget>[PrimaryLink('Create your first app', '/docs')]),
  ],
);
