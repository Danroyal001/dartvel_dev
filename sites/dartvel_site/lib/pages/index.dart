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

Widget _hero(BuildContext context) => Section(
      children: <Widget>[
        const Eyebrow('A FULL-STACK PLATFORM FOR FLUTTER'),
        const DVText('Flutter, all the way down.').modifier(
          DVModifier()
              .fontSize(Responsive.of(context).heroSize)
              .fontWeight(FontWeight.w800)
              .color(Palette.of(context).ink)
              .height(1.06),
        ),
        const DVText(
          'Write pages, models, backend functions, UI and business logic. '
          'Routing, typed clients, serialization, forms, admin and the server '
          'are generated, compiled or served for you.',
        ).modifier(
          DVModifier().fontSize(19).color(Palette.of(context).muted).height(1.65).width(640),
        ),
        DVBox.wrapLine(<Widget>[
          PrimaryLink('Get started', '/docs'),
          GhostLink('Documentation', '/docs'),
          GhostLink('Cloud', '/cloud'),
        ], spacing: 12),
        const DVText(
          'MIT licensed. Six packages on pub.dev, an npm launcher, a Homebrew '
          'tap, and self-contained binaries for five platforms.',
        ).modifier(DVModifier().fontSize(14).color(Palette.of(context).faint).width(560)),
      ],
    );

Widget _proof(BuildContext context) => Section(
      tint: true,
      children: <Widget>[
        const Eyebrow('WHAT IT LOOKS LIKE'),
        const Heading('A model is the whole feature.'),
        const DVText(
          'One annotated class gives you the typed client, the form with '
          'validation, the table, the admin surface, the public page and the '
          'sync. You do not write, or maintain, any of them.',
        ).modifier(DVModifier().fontSize(17).color(Palette.of(context).muted).height(1.6).width(620)),
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
        DVBox.wrapLine(<Widget>[
          const Chip_('Post.Form(...)'),
          const Chip_('Post.Page.fromId(...)'),
          const Chip_('Post.Table(...)'),
          const Chip_('DV.Admin'),
        ], spacing: 8),
        const DVText(
          'authorEmail is marked sensitive, so it is excluded from logs, AI '
          'context, traces, analytics, public serialization, search, the '
          'generated page, the table and the admin by default. It reaches a '
          'client only when a policy says so.',
        ).modifier(DVModifier().fontSize(15).color(Palette.of(context).muted).height(1.6).width(620)),
      ],
    );

Widget _pillars(BuildContext context) => Section(
      children: <Widget>[
        const Eyebrow('WHAT YOU GET'),
        DVBox.wrapLine(<Widget>[
          const Card_(
            'Pages',
            'A file under lib/pages is a route, with typed navigation and its '
            'loading and error states beside it.',
          ),
          const Card_(
            'Backend functions',
            'A Dart function becomes an endpoint, and the client that calls it '
            'is generated with it.',
          ),
          const Card_(
            'Signals',
            'context.signal, reactive models and DV.global. Operating on '
            'signals gives you a signal, so derived state composes.',
          ),
          const Card_(
            'A Rust runtime',
            'Axum and Tokio behind FFI, speaking HTTP/2 and HTTP/3, verified '
            'against a live server.',
          ),
          const Card_(
            'Native APIs',
            'DV.Platform on six platforms through FFI and jnigen. No platform '
            'channels anywhere.',
          ),
          const Card_(
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
        ).modifier(DVModifier().fontSize(16).color(Palette.of(context).muted).height(1.65).width(640)),
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
        ).modifier(DVModifier().fontSize(17).color(Palette.of(context).muted).height(1.65).width(660)),
        DVBox.wrapLine(<Widget>[
          const Stat('22', 'sections shipped'),
          const Stat('33', 'partial, and listed'),
          const Stat('13', 'targets that build'),
          const Stat('2', 'verified by running'),
        ], spacing: 14),
        const DVText(
          'A target says verified only where the command was run and the '
          'artifact inspected — never because a sibling target works.',
        ).modifier(DVModifier().fontSize(15).color(Palette.of(context).faint).height(1.6).width(620)),
      ],
    );


