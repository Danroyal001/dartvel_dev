import 'package:flutter/material.dart';
import '../components/site.dart';
import '../dartvel_client/dartvel_client.dart';

/// Where each step of the page is, so the contents can reach it.
///
/// Top-level and final rather than built in the page body: a GlobalKey has to
/// be the same object across rebuilds or the element it names is a different
/// one every frame, and the page body is rebuilt by every signal on it.
///
/// A map rather than nine fields because the contents list and the page walk
/// the same order, and two lists that have to agree are one list.
final Map<String, GlobalKey> kDocsSteps = <String, GlobalKey>{
  for (final String id in kDocsOrder) id: GlobalKey(),
};

/// The steps, in the order the page lays them out.
///
/// The number a reader sees comes from this position rather than being typed
/// into each heading, so inserting a step cannot leave two called "4".
const List<String> kDocsOrder = <String>[
  'install',
  'create',
  'pages',
  'models',
  'backend',
  'links',
  'state',
  'building',
  'honesty',
];

/// What each step is called in the contents.
const Map<String, String> kDocsTitles = <String, String>{
  'install': 'Install',
  'create': 'A new app',
  'pages': 'Pages',
  'models': 'Models',
  'backend': 'Backend functions',
  'links': 'Links',
  'state': 'State',
  'building': 'Building',
  'honesty': 'Before you depend on it',
};

/// A one-line description of each step, the way a docs index reads.
const Map<String, String> kDocsSummaries = <String, String>{
  'install': 'brew, npm or pub — the command is dartvel either way',
  'create': 'dartvel create, and what it writes',
  'pages': 'a file under lib/pages is a route',
  'models': 'one class gives you a table, a form and an admin',
  'backend': 'a function is an endpoint, typed on both sides',
  'links': 'a link is a link, not a tap handler',
  'state': 'signals compose because they are signals',
  'building': 'dartvel build, and the rest of the toolkit',
  'honesty': 'what is not built, and how to check',
};

/// Puts [id]'s step at the top of the screen.
///
/// Flutter has no fragment navigation, so a contents entry cannot be an
/// anchor the browser resolves. This is what an anchor does instead: find the
/// element the key names and scroll the enclosing scrollable to it.
///
/// Silent when the key has no element yet, which happens if somebody taps
/// during the first frame. A thrown error there would be a crash on a link
/// that works a moment later.
void dvGoToStep(String id) {
  final BuildContext? target = kDocsSteps[id]?.currentContext;
  if (target == null) return;
  Scrollable.ensureVisible(
    target,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeInOut,
  );
}

@DVPage(title: 'Documentation — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsPage(BuildContext context) => SingleChildScrollView(
      child: DVBox.list(<Widget>[
        const Section(
          children: <Widget>[
            Eyebrow('DOCUMENTATION'),
            Heading('From nothing to a running app.', level: 1),
            Body(
              'Dartvel needs the Dart and Flutter SDKs to build an '
              'application. It does not need them to run the CLI: that is a '
              'single self-contained binary.',
              width: 640,
            ),
          ],
        ),
        const DocsContents(),
        KeyedSubtree(key: kDocsSteps['install'], child: const Install()),
        KeyedSubtree(key: kDocsSteps['create'], child: const FirstApp()),
        KeyedSubtree(key: kDocsSteps['pages'], child: const Pages()),
        KeyedSubtree(key: kDocsSteps['models'], child: const Models()),
        KeyedSubtree(key: kDocsSteps['backend'], child: const Backend()),
        KeyedSubtree(key: kDocsSteps['links'], child: const Links()),
        KeyedSubtree(key: kDocsSteps['state'], child: const Signals()),
        KeyedSubtree(key: kDocsSteps['building'], child: const Building()),
        KeyedSubtree(key: kDocsSteps['honesty'], child: const Honesty()),
        const SiteFooter(),
      ], spacing: 0),
    );

/// The contents, which is what a docs page opens with.
///
/// Laravel's routing page begins with a nested list of everything on it, and
/// that list is most of why the page reads as organised rather than long. A
/// reader arriving with one question can see whether the page answers it
/// before scrolling, and get there in one tap if it does.
@DVFunctionalWidget()
Widget _docsContents(BuildContext context) => Section(
      tint: true,
      children: <Widget>[
        const Eyebrow('ON THIS PAGE'),
        DVBox.list(<Widget>[
          for (final String id in kDocsOrder)
            DocsContentsLine(
              id: id,
              number: kDocsOrder.indexOf(id) + 1,
            ),
        ], spacing: 2),
      ],
    );

/// One line of the contents: its number, its name, and what it covers.
@DVFunctionalWidget()
Widget _docsContentsLine(
  BuildContext context, {
  required String id,
  required int number,
}) {
  final Palette palette = Palette.of(context);
  // The last step is not a step: it is the thing to read before trusting any
  // of the others, and numbering it nine put it at the end of a queue rather
  // than beside the rest.
  final bool numbered = id != 'honesty' && id != 'links';
  final String label = kDocsTitles[id] ?? id;

  return DVBox(
    DVBox.wrapLine(<Widget>[
      DVText(numbered ? '$number' : '—').modifier(const DVModifier()
          .fontSize(13)
          .fontWeight(FontWeight.w700)
          .color(palette.faint)
          .width(22)),
      DVText(label).modifier(const DVModifier()
          .fontSize(15)
          .fontWeight(FontWeight.w600)
          .color(palette.accent)),
      DVText(kDocsSummaries[id] ?? '')
          .modifier(const DVModifier().fontSize(14).color(palette.muted)),
    ], spacing: 10),
    const DVModifier()
        .paddingSymmetric(vertical: 7)
        .semanticButton()
        .onTap(() => dvGoToStep(id)),
  );
}

@DVFunctionalWidget()
Widget _install() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('1 — INSTALL'),
        Heading('Three ways, same command.'),
        Body(
          'Whichever you choose, you end up typing dartvel. The published '
          'name carries a suffix because dartvel was taken on pub.dev by an '
          'unrelated package; the command does not.',
          width: 640,
        ),
        CodeBlock(<String>[
          '# Homebrew — a prebuilt binary, no SDK needed',
          'brew install Danroyal001/dartvel_dev/dartvel_dev',
          '',
          '# npm — downloads the same binary',
          'npx dartvel_dev --help',
          '',
          '# pub — if you already have Dart',
          'dart pub global activate dartvel_cli',
        ]),
        Body(
          'Check what it found: dartvel --version reports the CLI, the Dart '
          'SDK, Flutter and Shorebird, so a missing toolchain is visible '
          'before a build fails on it.',
          width: 640,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _firstApp() => const Section(
      children: <Widget>[
        Eyebrow('2 — A NEW APP'),
        Heading('dartvel create.'),
        CodeBlock(<String>[
          'dartvel create my_app',
          'cd my_app',
          'dartvel dev',
        ]),
        Body(
          'dartvel dev runs generation, the Flutter app and the backend '
          'together, and reloads only what changed: a page edit hot-reloads '
          'Flutter, a backend edit restarts the server, a Rust edit rebuilds '
          'the native library. A change to one does not restart the other.',
          width: 660,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _pages() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('3 — PAGES'),
        Heading('A file is a route.'),
        Body(
          'lib/pages/about.dart becomes /about. The annotated function is '
          'private and begins with an underscore; application code uses the '
          'generated public route, never the input declaration.',
          width: 640,
        ),
        CodeBlock(<String>[
          "@DVPage(title: 'About')",
          'Widget _aboutPage(BuildContext context) => DVBox.list(<Widget>[',
          "  const DVText('About us'),",
          ']);',
        ]),
        Body(
          'about.loading.dart and about.error.dart sit beside it and are '
          'wired up automatically. Navigation is typed against generated '
          'targets, so moving a page is a compile error rather than a 404.',
          width: 640,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _models() => const Section(
      children: <Widget>[
        Eyebrow('4 — MODELS'),
        Heading('One class, the whole feature.'),
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
        Body(
          'That gives you Post, Post.Form(...), Post.Table(...), '
          'Post.Page.fromId(...), the admin surface and the sync. Field '
          'metadata groups under the model annotation rather than spreading '
          'into standalone annotations.',
          width: 660,
        ),
        Body(
          'A sensitive field is excluded from logs, AI context, traces, '
          'analytics, public serialization, search, generated pages, tables '
          'and admin by default. Getting it to a client takes an explicit '
          'policy, which is the right way round.',
          width: 660,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _backend() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('5 — BACKEND'),
        Heading('A function is an endpoint.'),
        CodeBlock(<String>[
          '@DVBackendFunction()',
          'Future<List<Post>> recentPosts(DVContext context, int limit) async =>',
          '    DV.Database.query<Post>().orderByDesc(#createdAt).take(limit);',
        ]),
        Body(
          'The client to call it is generated with it. A first parameter of '
          'DVContext is injected rather than supplied by the caller. Return a '
          'Stream and it is served as server-sent events, with a typed client '
          'that consumes it.',
          width: 660,
        ),
        Body(
          'background: true and durable: true are sugar over @DVJob and '
          'DV.Queues rather than a separate mechanism, so work that must '
          'survive a restart is one flag away.',
          width: 660,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _links() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('LINKS'),
        Heading('A link, not a tap handler.'),
        CodeBlock(<String>[
          'DVNavLink(',
          '  to: DVRoutes.docs,',
          "  child: const DVText('Documentation'),",
          ')',
        ]),
        Body(
          'A Flutter app is a canvas, so almost nothing a link normally does '
          'exists unless the link does it. DVNavLink navigates with its '
          'padding as part of the hit area, announces itself as a link '
          'carrying its destination, takes keyboard focus and answers Enter, '
          'and opens the destination beside this page on a middle or '
          'modifier click.',
          width: 660,
        ),
        Body(
          'It also preloads. Every page is its own deferred bundle, and a '
          'link fetches the one it points at once it has sat on screen for '
          'a moment, or as soon as a pointer reaches it — the same work, a '
          'few hundred milliseconds earlier. On the web it prefetches the '
          'page itself too: its prerendered HTML, and the images it opens '
          'with. A mouse follows the link when the button goes down, not '
          'when it comes back up.',
          width: 660,
        ),
        Body(
          'And it previews. Resting on a link shows a card of where it goes; '
          'on a phone, a long press does. That is the part iOS gives to '
          'Safari and nothing gives to anyone else, and it works here because '
          'Dartvel built the router and can build the destination.',
          width: 660,
        ),
        CodeBlock(<String>[
          'DVNavLink(',
          '  to: DVRoutes.report,',
          '  preload: DVLinkPreload.immediate,  // none | hover | visible | immediate',
          '  preview: DVLinkPreview.none,       // none | auto',
          "  child: const DVText('Annual report'),",
          ')',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _signals() => const Section(
      children: <Widget>[
        Eyebrow('6 — STATE'),
        Heading('Signals compose because they are signals.'),
        CodeBlock(<String>[
          'final price = context.signal(10);',
          'final quantity = context.signal(3);',
          '',
          '// A signal, tracking both sources.',
          'final total = price * quantity;',
          'final inStock = stock > 0;',
        ]),
        Body(
          'Operating on signals returns a signal. There is no computed() and '
          'no DVComputed type, deliberately: the result of an operation is '
          'already reactive, and composes for that reason.',
          width: 660,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _building() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('7 — BUILDING'),
        Heading('dartvel build.'),
        CodeBlock(<String>[
          'dartvel build web        # static output for any host',
          'dartvel build linux      # desktop, runtime linked in',
          'dartvel build android    # apk',
          'dartvel build tizen      # Samsung TVs, via the vendor embedder',
          'dartvel build            # every target available on this host',
        ]),
        Body(
          'Generation runs as part of the build; there is no separate step to '
          'remember. A build checks host support and required tooling before '
          'doing any work, so it never starts something it cannot finish, and '
          'it names the missing tool rather than failing partway.',
          width: 660,
        ),
        Body(
          'Licence-gated SDKs are never installed unattended. Xcode, Visual '
          'Studio, the Android SDK and Tizen Studio print instructions '
          'instead.',
          width: 660,
        ),
        Heading('The rest of the toolkit.', level: 3),
        CodeBlock(<String>[
          'dartvel doctor                        # host, tooling, and a kiosk policy that cannot be honoured',
          'dartvel inspect windows               # the declared windowing, and what a running app has open',
          'dartvel analyze performance           # what the running app measured: degradations per call site, timings, findings',
          'dartvel inspect kiosk                 # the effective kiosk policy per target and per window, each value with its source',
          'dartvel key generate | rotate | status # the application key, in the platform key store',
          'dartvel capture pwa-sync --web build/web  # the worker\'s outbox, in a real browser',
          'dartvel publish play                  # a built app to a store, refused before the upload rather than during',
        ]),
        Body(
          'Each is the same rule as build: it says what it found and what it '
          'could not do, and never reports a step it skipped as done. The '
          'key store is whichever the platform has custody for -- the Secret '
          'Service, DPAPI, the Keychain -- and the command says which.',
          width: 660,
        ),
      ],
    );

@DVFunctionalWidget()
Widget _honesty() => const Section(
      children: <Widget>[
        Eyebrow('BEFORE YOU DEPEND ON IT'),
        Heading('Read what is not built.'),
        Body(
          'Dartvel is published early. The repository records per-section '
          'status with two independent labels — how much the public surface '
          'can still move, and how much is built — and a tool fails the build '
          'when a section claims to be built and the evidence it names does '
          'not exist.',
          width: 660,
        ),
        Body(
          'Thirteen sections are a frozen public contract with an unfinished '
          'implementation behind them. They are marked that way rather than '
          'implied to work.',
          width: 660,
        ),
        DVBox.wrapLine(<Widget>[
          GhostLink('What works today', '/features'),
          GhostLink('Cloud', '/cloud'),
        ], spacing: 12),
      ],
    );

