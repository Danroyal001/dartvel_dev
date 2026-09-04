import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/deck.dart';
import '../components/site.dart';

@DVPage(title: 'Dartvel — Flutter, full stack', showAppBar: false)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const Deck(
      // A deck rather than a scroll. Each of these is a separate claim, and a
      // landing page that runs them together as one long column asks the
      // reader to find the boundaries themselves.
      //
      // The layout gives this the height the header does not take, so the deck
      // is the page's only scrollable. Nested inside another one it never
      // received a gesture, and no wheel or arrow key moved a slide.
      slides: <(String, Widget)>[
        ('Overview', HeroSection()),
        ('Models', Proof()),
        ('What you get', Pillars()),
        ('Design', FromDesign()),
        ('Targets', Targets()),
        ('vs Expo', ExpoComparison()),
        ('Status', Honest()),
        ('Links', SiteFooter()),
      ],
    );

@DVFunctionalWidget()
Widget _heroSection(BuildContext context) {
  final bool narrow = context.screen.isMobile;
  const Widget copy = HeroCopy();
  return Section(
    glow: true,
    children: <Widget>[
      // Two columns where there is room. The hero was one left-aligned
      // column with the right half of the window empty, which reads as a
      // document rather than as a product.
      if (narrow)
        copy
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
Widget _heroCopy(BuildContext context) => DVBox.list(
      <Widget>[
        const Eyebrow('A FULL-STACK PLATFORM FOR FLUTTER'),
        const DVText('Flutter, all the way down.').modifier(
          const DVModifier()
              .fontSize(context.screen.value<double>(mobile: 36, desktop: 54))
              .fontWeight(FontWeight.w800)
              .color(Palette.of(context).ink)
              .height(1.06)
              // The site's one h1.
              .semanticHeading(1),
        ),
        // The positioning line. Four comparisons rather than one, because
        // "Flutter's Laravel" alone reads as "a backend for Flutter" and
        // undersells the half of it that is the client.
        const DVText("Flutter's Laravel. Flutter's Expo. Flutter's Next.js. "
                "Flutter's Hasura.")
            .modifier(
          const DVModifier()
              .fontSize(context.screen.value<double>(mobile: 17, desktop: 20))
              .fontWeight(FontWeight.w600)
              .color(Palette.of(context).accent)
              .height(1.45)
              .maxWidth(640),
        ),
        const DVText(
          'Write pages, models, backend functions, UI and business logic. '
          'Routing, typed clients, serialization, forms, admin and the server '
          'are generated, compiled or served for you.',
        ).modifier(
          const DVModifier().fontSize(19).color(Palette.of(context).muted).height(1.65).width(640),
        ),
        // The two things people do not expect a Flutter framework to do, at
        // the top of the page rather than three slides down where they were.
        const DVText(
          'Import a Figma file and get pages you can edit and export as '
          'ordinary Dart. Build the same application for a terminal, with no '
          'GUI code linked in.',
        ).modifier(
          const DVModifier().fontSize(17).color(Palette.of(context).muted).height(1.6).width(600),
        ),
        const DVBox.wrapLine(<Widget>[
          PrimaryLink('Get started', '/docs'),
          GhostLink('Documentation', '/docs'),
          GhostLink('Cloud', '/cloud'),
        ], spacing: 12),
        const DVText(
          'MIT licensed. Six packages on pub.dev, an npm launcher, a Homebrew '
          'tap, and self-contained binaries for five platforms.',
        ).modifier(const DVModifier().fontSize(14).color(Palette.of(context).faint).width(560)),
      ],
      spacing: 20,
    );

/// A terminal beside the hero, so the right half of the window shows the
/// product rather than nothing.
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
            // Coloured the way the terminal actually is. A screenshot of a
            // terminal in one flat grey is a picture of a wall; the prompt,
            // what you type and what it answers are three different things.
            child: Typewriter(
              style: TextStyle(
                  fontFamily: 'RobotoMono',
                  fontFamilyFallback: <String>[
                    'Menlo', 'Consolas', 'monospace',
                  ],
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
                  text: '  routes      ',
                  style: TextStyle(color: Color(0xFF7080A8)),
                ),
                TextSpan(text: '4 pages, typed targets\n'),
                TextSpan(
                  text: '  client      ',
                  style: TextStyle(color: Color(0xFF7080A8)),
                ),
                TextSpan(text: 'generated\n'),
                TextSpan(
                  text: '  backend     ',
                  style: TextStyle(color: Color(0xFF7080A8)),
                ),
                TextSpan(
                  text: ':3000',
                  style: TextStyle(color: Color(0xFF7DCFFF)),
                ),
                TextSpan(text: '  (axum)\n'),
                TextSpan(
                  text: '  flutter     ',
                  style: TextStyle(color: Color(0xFF7080A8)),
                ),
                TextSpan(
                  text: ':8080',
                  style: TextStyle(color: Color(0xFF7DCFFF)),
                ),
                TextSpan(text: '  hot reload\n\n'),
                TextSpan(
                text: '  ready in 1.9s',
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
Widget _proof(BuildContext context) => Section(
      tint: true,
      children: <Widget>[
        const Eyebrow('WHAT IT LOOKS LIKE'),
        const Heading('A model is the whole feature.'),
        const DVText(
          'One annotated class gives you the typed client, the form with '
          'validation, the table, the admin surface, the public page and the '
          'sync. You do not write, or maintain, any of them.',
        ).modifier(const DVModifier().fontSize(17).color(Palette.of(context).muted).height(1.6).width(620)),
        const CodeBlock(<String>[
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
        const DVBox.wrapLine(<Widget>[
          SiteChip('Post.Form(...)'),
          SiteChip('Post.Page.fromId(...)'),
          SiteChip('Post.Table(...)'),
          SiteChip('DV.Admin'),
        ], spacing: 8),
        const DVText(
          'authorEmail is marked sensitive, so it is excluded from logs, AI '
          'context, traces, analytics, public serialization, search, the '
          'generated page, the table and the admin by default. It reaches a '
          'client only when a policy says so.',
        ).modifier(const DVModifier().fontSize(15).color(Palette.of(context).muted).height(1.6).width(620)),
      ],
    );

@DVFunctionalWidget()
Widget _pillars(BuildContext context) => const Section(
      children: <Widget>[
        Eyebrow('WHAT YOU GET'),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'Pages',
            'A file under lib/pages is a route, with typed navigation and its '
            'loading and error states beside it.',
          ),
          SiteCard(
            'Backend functions',
            'A Dart function becomes an endpoint, and the client that calls it '
            'is generated with it.',
          ),
          SiteCard(
            'Signals',
            'context.signal, reactive models and DV.global. Operating on '
            'signals gives you a signal, so derived state composes.',
          ),
          SiteCard(
            'A Rust runtime',
            'Axum and Tokio behind FFI, speaking HTTP/2 and HTTP/3, verified '
            'against a live server.',
          ),
          SiteCard(
            'Native APIs',
            'DV.Platform on six platforms through FFI and jnigen. No platform '
            'channels anywhere.',
          ),
          SiteCard(
            'One toolkit',
            'dartvel dev, build, test, db, queue, deploy. Generation runs as '
            'part of the build.',
          ),
        ], spacing: 16),
      ],
    );

// The strongest thing on this site and it was on the cloud page only, where
// somebody has to go looking for it.
@DVFunctionalWidget()
Widget _fromDesign(BuildContext context) => const Section(
      children: <Widget>[
        Eyebrow('FROM A FIGMA FILE'),
        Heading('A design, not a picture of one.'),
        Body(
          'Paste a file URL. Every top-level frame becomes a page you can '
          'open in the builder, edit, and export as an ordinary @DVPage — '
          'files you own, in your repository, with the images in them.',
          width: 660,
        ),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'It arrives as layout',
            'Auto-layout becomes rows and lists with the designer\'s own '
            'spacing and alignment. Padding keeps all four sides. A frame '
            'placed by hand keeps its coordinates, relative to the frame it '
            'sits in rather than to the artboard it was drawn on.',
          ),
          SiteCard(
            'And as the design',
            'Typefaces, line heights, shadows, gradients, corners that '
            'differ, how each image fills its frame, how many lines a title '
            'gets. A node keeps the size it was drawn at only where the '
            'designer fixed it, so the result is not pinned to the width of '
            'the artboard.',
          ),
          SiteCard(
            'Icons too',
            'An icon is vector paths and carries no image, so Figma is asked '
            'to render each one and the picture is kept. That is the '
            'difference between a design that arrives with everything but its '
            'icons and one that arrives.',
          ),
          SiteCard(
            'Nothing expires',
            'Figma\'s image URLs are temporary. Every image is downloaded '
            'and kept, so a design imported today does not show broken '
            'pictures a fortnight from now.',
          ),
          SiteCard(
            'A screen that scrolls',
            'Almost every screen is taller than the phone it was drawn on. '
            'Figma places everything absolutely, so the import measures that '
            'rather than guessing, and the page scrolls instead of showing '
            'the overflow stripe.',
          ),
          SiteCard(
            'Or a project on disk',
            'The pages go live in the running application without a rebuild, '
            'or come out as a Flutter project: each page the file its route '
            'names, each image an asset, with the pubspec lines that make it '
            'build.',
          ),
        ], spacing: 16),
        Body(
          'Figma import is a Studio Pro feature. The page builder underneath '
          'it — drag and drop, an inspector, undo, breakpoints, one-click '
          'export — is free.',
          width: 660,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _targets(BuildContext context) => Section(
      // The one band that stops the scroll. A page that is eight shades of
      // the same cream reads as one very long section however good the type
      // is, and fifteen chips is the thing on this page worth stopping at.
      dark: true,
      children: <Widget>[
        const Eyebrow('ONE CODEBASE', onDark: true),
        const Heading('Fifteen build targets.', onDark: true),
        DVBox.wrapLine(<Widget>[
          for (final String target in const <String>[
            'web', 'linux', 'macOS', 'windows', 'android', 'iOS', 'tvOS',
            'Fire OS', 'Tizen', 'Sony eLinux', 'webOS', 'VS Code',
            'Chrome', 'Firefox', 'terminal',
          ])
            SiteChip(target, onDark: true),
        ], spacing: 8),
        const DVText(
          'Embedded and television targets ride the platform vendor’s own '
          'Flutter embedder rather than plain flutter build, each pinned in a '
          'fork so the engine and the Flutter version stay aligned. A build '
          'checks host support and tooling before doing any work, so it never '
          'starts something it cannot finish.',
        ).modifier(const DVModifier().fontSize(16).color(const Color(0xFF9AA6C4)).height(1.65).width(640)),
        const SizedBox(height: 8),
        // The last chip in that row is the one worth a sentence: a Flutter
        // application drawing in a terminal is not a thing people expect to
        // be on the list.
        const DVText(
          'The last of those is a terminal. dartvel build linux-cli links the '
          'terminal backend and no GUI code; the desktop build links the GUI '
          'and no terminal code; an application that asks for both resolves '
          'at launch — --tui, or the prompt when there is no display. Nothing '
          'pays for a mode it will never use. The embedder is run in a pty in '
          'CI and its escape sequences counted, because a build that produced '
          'a GUI binary and called it a TUI is exactly what happened once. A '
          'Dartvel application in a terminal is the half still landing: '
          'Flutter cannot configure a project\'s native assets for a bundle '
          'build on Linux, so what CI renders today is a plain Flutter app.',
        ).modifier(const DVModifier().fontSize(16).color(const Color(0xFF9AA6C4)).height(1.65).width(640)),
        const SizedBox(height: 8),
        // Breadth only. The section below already counts shipped spec
        // sections, and two numeric rows a screen apart both saying 22 read
        // as the same claim made twice.
        const Stats(onDark: true, <Figure>[
          Figure('15', 'build targets'),
          Figure('6', 'packages on pub.dev'),
          Figure('5', 'self-contained binaries'),
          Figure('1', 'command to build any of them'),
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _honest(BuildContext context) => Section(
      children: <Widget>[
        const Eyebrow('WHERE IT ACTUALLY IS'),
        const Heading('Published early, and stated plainly.'),
        const DVText(
          'Dartvel is not finished, and the repository says exactly how '
          'unfinished. Every spec section carries two labels — how much the '
          'public surface can still move, and how much is built — checked by a '
          'tool that fails when a section claims to be built and the evidence '
          'it names does not exist.',
        ).modifier(const DVModifier().fontSize(17).color(Palette.of(context).muted).height(1.65).width(660)),
        const DVBox.wrapLine(<Widget>[
          Stat('33', 'sections shipped'),
          Stat('22', 'partial, and listed'),
          Stat('14', 'targets that build'),
          Stat('4', 'verified by running'),
        ], spacing: 14),
        const DVText(
          'A target says verified only where the command was run and the '
          'artifact inspected — never because a sibling target works.',
        ).modifier(const DVModifier().fontSize(15).color(Palette.of(context).faint).height(1.6).width(620)),
      ],
    );




/// What "Flutter's Expo" covers, and the one part it does not.
///
/// People arriving from Expo want one of three things, and claiming the name
/// without saying which would be the kind of marketing this page is trying not
/// to be. The third row is the honest gap, and it is on the page rather than
/// in an issue.
@DVFunctionalWidget()
Widget _expoComparison(BuildContext context) => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('IF YOU CAME LOOKING FOR EXPO'),
        Heading('Two of the three, and we say which.'),
        Body(
          'Expo bundles three separate things people mean by its name. Dartvel '
          'covers two of them outright. The third is a hosted build service, '
          'and we do not run one.',
        ),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'The SDK',
            'Auth, push, storage, database, queues, AI and platform APIs are '
            'framework services, not a starter template you copy once and '
            'maintain forever.',
          ),
          SiteCard(
            'Over-the-air updates',
            'dartvel updates release, patch and rollback drive Shorebird, the '
            'Flutter code-push framework. The CLI works today; the runtime '
            'DV.Updates binding does not.',
          ),
          SiteCard(
            'Cloud builds and store submission',
            'Not covered. Dartvel writes GitHub Actions and Codemagic config '
            'and deploys web and function targets. It does not manage signing '
            'certificates or provisioning profiles, and there is no hosted '
            'build service. Expo Launch does that job.',
          ),
        ], spacing: 16),
        Body(
          'Native folders stay out of your way either way: dartvel build '
          'targets fifteen platforms, and you never open android/ or ios/ to '
          'prototype.',
          width: 640,
        ),
      ],
    );
