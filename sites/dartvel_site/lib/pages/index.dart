import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

@DVPage(title: 'Dartvel — Flutter, full stack', showAppBar: false)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => buildIndexPage(context);

Widget buildIndexPage(BuildContext context) => SitePage(
      current: '/',
      children: <Widget>[
        _hero(context),
        _proof(context),
        _pillars(context),
        _targets(context),
        _honest(context),
      ],
    );

Widget _hero(BuildContext context) {
  final bool narrow = Responsive.of(context).narrow;
  final Widget copy = _heroCopy(context);
  return Section(
    children: <Widget>[
      // Two columns where there is room. The hero was one left-aligned
      // column with the right half of the window empty, which reads as a
      // document rather than as a product.
      if (narrow)
        copy
      else
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 6, child: copy),
            const SizedBox(width: 48),
            const Expanded(flex: 5, child: _HeroTerminal()),
          ],
        ),
    ],
  );
}

Widget _heroCopy(BuildContext context) => DVBox.list(
      <Widget>[
        const Eyebrow('A FULL-STACK PLATFORM FOR FLUTTER'),
        const DVText('Flutter, all the way down.').modifier(
          const DVModifier()
              .fontSize(Responsive.of(context).heroSize)
              .fontWeight(FontWeight.w800)
              .color(Palette.of(context).ink)
              .height(1.06)
              // The site's one h1.
              .semanticHeading(1),
        ),
        const DVText(
          'Write pages, models, backend functions, UI and business logic. '
          'Routing, typed clients, serialization, forms, admin and the server '
          'are generated, compiled or served for you.',
        ).modifier(
          const DVModifier().fontSize(19).color(Palette.of(context).muted).height(1.65).width(640),
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
class _HeroTerminal extends StatelessWidget {
  const _HeroTerminal();

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
                  Color(0xFFFF5F57),
                  Color(0xFFFEBC2E),
                  Color(0xFF28C840),
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
            child: SelectableText(
              '\$ dartvel create shop\n'
              '\$ cd shop && dartvel dev\n'
              '\n'
              '  routes      4 pages, typed targets\n'
              '  client      generated\n'
              '  backend     :3000  (axum)\n'
              '  flutter     :8080  hot reload\n'
              '\n'
              '  ready in 1.9s',
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontFamilyFallback: <String>['Menlo', 'Consolas', 'monospace'],
                fontSize: 12.5,
                height: 1.75,
                color: Color(0xFFD7E1F5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
          Chip_('Post.Form(...)'),
          Chip_('Post.Page.fromId(...)'),
          Chip_('Post.Table(...)'),
          Chip_('DV.Admin'),
        ], spacing: 8),
        const DVText(
          'authorEmail is marked sensitive, so it is excluded from logs, AI '
          'context, traces, analytics, public serialization, search, the '
          'generated page, the table and the admin by default. It reaches a '
          'client only when a policy says so.',
        ).modifier(const DVModifier().fontSize(15).color(Palette.of(context).muted).height(1.6).width(620)),
      ],
    );

Widget _pillars(BuildContext context) => const Section(
      children: <Widget>[
        Eyebrow('WHAT YOU GET'),
        DVBox.wrapLine(<Widget>[
          Card_(
            'Pages',
            'A file under lib/pages is a route, with typed navigation and its '
            'loading and error states beside it.',
          ),
          Card_(
            'Backend functions',
            'A Dart function becomes an endpoint, and the client that calls it '
            'is generated with it.',
          ),
          Card_(
            'Signals',
            'context.signal, reactive models and DV.global. Operating on '
            'signals gives you a signal, so derived state composes.',
          ),
          Card_(
            'A Rust runtime',
            'Axum and Tokio behind FFI, speaking HTTP/2 and HTTP/3, verified '
            'against a live server.',
          ),
          Card_(
            'Native APIs',
            'DV.Platform on six platforms through FFI and jnigen. No platform '
            'channels anywhere.',
          ),
          Card_(
            'One toolkit',
            'dartvel dev, build, test, db, queue, deploy. Generation runs as '
            'part of the build.',
          ),
        ], spacing: 16),
      ],
    );

Widget _targets(BuildContext context) => Section(
      tint: true,
      children: <Widget>[
        const Eyebrow('ONE CODEBASE'),
        const Heading('Fifteen build targets.'),
        DVBox.wrapLine(<Widget>[
          for (final String target in const <String>[
            'web', 'linux', 'macOS', 'windows', 'android', 'iOS', 'tvOS',
            'Fire OS', 'Tizen', 'Sony eLinux', 'webOS', 'VS Code',
            'Chrome', 'Firefox', 'terminal',
          ])
            Chip_(target),
        ], spacing: 8),
        const DVText(
          'Embedded and television targets ride the platform vendor’s own '
          'Flutter embedder rather than plain flutter build, each pinned in a '
          'fork so the engine and the Flutter version stay aligned. A build '
          'checks host support and tooling before doing any work, so it never '
          'starts something it cannot finish.',
        ).modifier(const DVModifier().fontSize(16).color(Palette.of(context).muted).height(1.65).width(640)),
      ],
    );

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
          Stat('22', 'sections shipped'),
          Stat('33', 'partial, and listed'),
          Stat('13', 'targets that build'),
          Stat('2', 'verified by running'),
        ], spacing: 14),
        const DVText(
          'A target says verified only where the command was run and the '
          'artifact inspected — never because a sibling target works.',
        ).modifier(const DVModifier().fontSize(15).color(Palette.of(context).faint).height(1.6).width(620)),
      ],
    );


