import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

const _ink = Color(0xFF0B1020);
const _muted = Color(0xFF5A6478);
const _accent = Color(0xFF2F6BFF);
const _rule = Color(0xFFE3E7EF);

@DVPage(
  title: 'Dartvel — Flutter, full stack',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => buildIndexPage(context);

Widget buildIndexPage(BuildContext context) => DVBox.list([
      _hero(),
      _install(),
      _whatYouWrite(),
      _targets(),
      _honesty(),
      _footer(),
    ]).modifier(
      const DVModifier().padding(0),
    );

Widget _hero() => DVBox.list([
      const DVText('DARTVEL').modifier(
        DVModifier()
            .fontSize(13)
            .fontWeight(FontWeight.w700)
            .color(_accent)
            .letterSpacing(2.4),
      ),
      const DVText('Flutter, full stack.').modifier(
        DVModifier()
            .fontSize(52)
            .fontWeight(FontWeight.w800)
            .color(_ink)
            .height(1.08),
      ),
      const DVText(
        'You write pages, models, backend functions, UI and business logic. '
        'Routing, clients, serialization, forms, admin and the server are '
        'generated, compiled or served.',
      ).modifier(
        DVModifier().fontSize(19).color(_muted).height(1.6).width(620),
      ),
    ], spacing: 18).modifier(
      const DVModifier().padding(48).width(1040).align(Alignment.topLeft),
    );

Widget _install() => DVBox.list([
      const DVText('Install').modifier(_sectionLabel()),
      DVBox.list([
        _command('brew install Danroyal001/dartvel_dev/dartvel_dev'),
        _command('npx dartvel_dev --help'),
        _command('dart pub global activate dartvel_cli'),
      ], spacing: 10),
      const DVText(
        'The CLI is a single self-contained binary. Nothing has to be '
        'installed to run it. Building an app still needs Flutter, for '
        'whichever target you are building.',
      ).modifier(DVModifier().fontSize(15).color(_muted).width(620)),
    ], spacing: 16).modifier(
      const DVModifier().padding(48).width(1040),
    );

Widget _command(String text) => DVText(text).modifier(
      DVModifier()
          .fontSize(14)
          
          .color(_ink)
          .backgroundColor(const Color(0xFFF4F6FB))
          .padding(14)
          .rounded(8),
    );

Widget _whatYouWrite() => DVBox.list([
      const DVText('What you write').modifier(_sectionLabel()),
      DVBox.wrapLine([
        _card('Pages', 'A file in lib/pages is a route. Typed navigation, '
            'loading and error states beside it.'),
        _card('Models', '@DVModel generates the client, the form, the table, '
            'the admin surface and the sync.'),
        _card('Backend functions', 'A Dart function becomes an endpoint. The '
            'client to call it is generated.'),
        _card('UI', 'DVBox and DVText with fluent styling, on one layout '
            'system across every target.'),
      ], spacing: 16),
    ], spacing: 16).modifier(
      const DVModifier().padding(48).width(1040),
    );

Widget _card(String title, String body) => DVBox.list([
      DVText(title).modifier(
        DVModifier().fontSize(17).fontWeight(FontWeight.w700).color(_ink),
      ),
      DVText(body).modifier(
        DVModifier().fontSize(14).color(_muted).height(1.55),
      ),
    ], spacing: 8).modifier(
      DVModifier()
          .padding(20)
          .rounded(12)
          .width(300)
          .backgroundColor(const Color(0xFFFAFBFD)),
    );

Widget _targets() => DVBox.list([
      const DVText('One codebase, fifteen targets').modifier(_sectionLabel()),
      DVBox.wrapLine([
        for (final String target in const <String>[
          'web', 'linux', 'macOS', 'windows', 'android', 'iOS', 'tvOS',
          'Fire OS', 'Tizen', 'Sony eLinux', 'webOS', 'VS Code',
          'Chrome', 'Firefox', 'terminal',
        ])
          DVText(target).modifier(
            DVModifier()
                .fontSize(13)
                .color(_ink)
                .backgroundColor(const Color(0xFFF4F6FB))
                .padding(10)
                .rounded(999),
          ),
      ], spacing: 8),
      const DVText(
        'Embedded and television targets ride the platform vendor’s own '
        'Flutter embedder rather than plain flutter build, each pinned in a '
        'fork so the engine and the Flutter version stay aligned.',
      ).modifier(DVModifier().fontSize(15).color(_muted).width(620)),
    ], spacing: 16).modifier(
      const DVModifier().padding(48).width(1040),
    );

Widget _honesty() => DVBox.list([
      const DVText('Published early, and stated plainly').modifier(
        _sectionLabel(),
      ),
      const DVText(
        'Dartvel is not finished. Per-section status lives in the repository '
        'and is checked by a tool that fails when a section claims to be '
        'built and the evidence it names does not exist. A frozen public '
        'contract with nothing behind it yet is marked as such rather than '
        'implied to work, and what is absent is written down next to what is '
        'present.',
      ).modifier(DVModifier().fontSize(16).color(_muted).height(1.6).width(660)),
      const DVText(
        'Build status per target says verified only where the command was run '
        'and the artifact inspected — never because a sibling target works.',
      ).modifier(DVModifier().fontSize(16).color(_muted).height(1.6).width(660)),
    ], spacing: 14).modifier(
      const DVModifier().padding(48).width(1040),
    );

Widget _footer() => DVBox.list([
      DVBox.wrapLine([
        _link('GitHub', 'github.com/Danroyal001/dartvel_dev'),
        _link('pub.dev', 'pub.dev/packages/dartvel_dev'),
        _link('npm', 'npmjs.com/package/dartvel_dev'),
      ], spacing: 20),
      const DVText('MIT licensed.').modifier(
        DVModifier().fontSize(13).color(_muted),
      ),
    ], spacing: 12).modifier(
      const DVModifier().padding(48).width(1040),
    );

Widget _link(String label, String href) => DVText(label).modifier(
      DVModifier().fontSize(14).color(_accent).fontWeight(FontWeight.w600),
    );

DVModifier _sectionLabel() => DVModifier()
    .fontSize(12)
    .fontWeight(FontWeight.w700)
    .color(_muted)
    .letterSpacing(1.6);
