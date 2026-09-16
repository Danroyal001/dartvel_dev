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
  'install': 'brew, npm or pub. The command is dartvel.',
  'create': 'dartvel create, and what it writes',
  'pages': 'a file under lib/pages is a route',
  'models': 'one class gives you a form, a table and an admin',
  'backend': 'a function is an endpoint, typed on both sides',
  'links': 'DVNavLink navigates, preloads and previews',
  'state': 'operators on signals return signals',
  'building': 'dartvel build, doctor, inspect and explain',
  'honesty': 'how to check what is built',
};

/// Whether [id] is counted as a step in the contents. Links and the closing
/// check are read alongside the steps rather than as one of them.
bool dvDocsStepIsNumbered(String id) => id != 'honesty' && id != 'links';

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

@DVPage(title: 'Dartvel docs: install and build your first app', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsPage(BuildContext context) => SingleChildScrollView(
      child: DVBox.list(<Widget>[
        const Section(
          children: <Widget>[
            Eyebrow('DOCUMENTATION'),
            Heading('Install Dartvel and run your first app.', level: 1),
            Bullets(<String>[
              'The brew and npm installs are one binary that runs without Dart.',
              'You need Flutter to build an app for a target.',
            ]),
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
              // Counted among the numbered steps only, so an unnumbered entry
              // does not leave a gap after it.
              number: kDocsOrder
                      .take(kDocsOrder.indexOf(id))
                      .where(dvDocsStepIsNumbered)
                      .length +
                  1,
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
  final bool numbered = dvDocsStepIsNumbered(id);
  final String label = kDocsTitles[id] ?? id;

  return DVBox(
    // The number keeps its own column, so a title and summary that wrap on a
    // phone wrap under the title rather than back under the number.
    DVBox.row(<Widget>[
      DVText(numbered ? '$number' : '•').modifier(const DVModifier()
          .fontSize(13)
          .fontWeight(FontWeight.w700)
          .color(palette.faint)
          .width(22)),
      Expanded(
        child: DVBox.wrapLine(<Widget>[
          DVText(label).modifier(const DVModifier()
              .fontSize(15)
              .fontWeight(FontWeight.w600)
              .color(palette.accent)),
          DVText(kDocsSummaries[id] ?? '')
              .modifier(const DVModifier().fontSize(14).color(palette.muted)),
        ], spacing: 10, crossAlign: DVCrossAlign.center),
      ),
    ], spacing: 10, crossAlign: DVCrossAlign.start),
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
        Eyebrow('INSTALL'),
        Heading('Install the CLI with brew, npm or pub.'),
        CodeBlock(<String>[
          '# Homebrew: a prebuilt binary, no SDK needed',
          'brew install Danroyal001/dartvel_dev/dartvel_dev',
          '',
          '# npm: downloads the same binary',
          'npx dartvel_dev --help',
          '',
          '# pub: if you already have Dart',
          'dart pub global activate dartvel_cli',
        ]),
        Bullets(<String>[
          'The package is dartvel_dev. The command is dartvel.',
          'dartvel --version shows the Dart, Flutter and Shorebird it found.',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _firstApp() => const Section(
      children: <Widget>[
        Eyebrow('A NEW APP'),
        Heading('Create an app and start the dev loop.'),
        CodeBlock(<String>[
          'dartvel create my_app',
          'cd my_app',
          'dartvel dev',
        ]),
        Bullets(<String>[
          'dartvel dev runs code generation, the Flutter app and the backend '
              'together.',
          'A page edit hot-reloads Flutter. A backend edit restarts only the '
              'server.',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _pages() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('PAGES'),
        Heading('Add a page by adding a file.'),
        CodeBlock(<String>[
          '// lib/pages/about.dart is served at /about',
          "@DVPage(title: 'About')",
          'Widget _aboutPage(BuildContext context) => DVBox.list(<Widget>[',
          "  const DVText('About us'),",
          ']);',
        ]),
        Bullets(<String>[
          'The annotated function is private. Your code links to the generated '
              'route.',
          'about.loading.dart and about.error.dart sit beside it and are wired '
              'up for you.',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _models() => const Section(
      children: <Widget>[
        Eyebrow('MODELS'),
        Heading('Declare a model and get its form, table and admin.'),
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
          'You get Post, Post.Form(...), Post.Table(...), Post.Admin() and '
              'Post.Page.fromId(...).',
          'Field settings live under @DVModel, as in @DVModel.pageTitle().',
          'A sensitive field reaches a client only through an explicit policy.',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _backend() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('BACKEND'),
        Heading('Write a server function and call it from a page.'),
        CodeBlock(<String>[
          '// Server',
          '@DVBackendFunction()',
          'Future<Post?> _getPost(String id) => Post.find(id);',
          '',
          '// Client',
          'final Post? post = await getPost(id);',
        ]),
        Bullets(<String>[
          'Make DVContext the first parameter and it is injected. The client '
              'never passes it.',
          'Return a Stream and the function is served as server-sent events.',
          'background: true or durable: true puts the call on the job queue.',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _links() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('LINKS'),
        Heading('Use DVNavLink for every link.'),
        CodeBlock(<String>[
          'DVNavLink(',
          '  to: DVRoutes.docs,',
          "  child: const DVText('Documentation'),",
          ')',
        ]),
        Bullets(<String>[
          'Tab, Enter and middle-click work the way they do on a web link.',
          'The target page starts loading after 300 ms on screen, or when the '
              'pointer reaches it.',
          'Hover, or long press on a phone, to see a preview of the page.',
        ]),
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
        Eyebrow('STATE'),
        Heading('Combine signals with ordinary operators.'),
        CodeBlock(<String>[
          'final price = context.signal(10);',
          'final quantity = context.signal(3);',
          'final stock = context.signal(5);',
          '',
          '// Each of these is a signal that tracks its sources.',
          'final total = price * quantity;',
          'final inStock = stock > 0;',
        ]),
        Bullets(<String>[
          'total updates when price or quantity changes.',
          'There is no computed() or DVComputed type to learn.',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _building() => const Section(
      tint: true,
      children: <Widget>[
        Eyebrow('BUILDING'),
        Heading('Build any target with one command.'),
        CodeBlock(<String>[
          'dartvel build web        # static files for any host',
          'dartvel build linux      # desktop app',
          'dartvel build android    # apk',
          'dartvel build tizen      # Samsung TVs, through the vendor embedder',
          'dartvel build            # every target this machine can build',
        ]),
        Bullets(<String>[
          'Code generation runs first, so there is no separate step.',
          'It checks the host and tools before it starts, and names what is '
              'missing.',
          'Xcode, Visual Studio, the Android SDK and Tizen Studio are never '
              'installed for you.',
        ]),
        Heading('Check your project.', level: 3),
        CodeBlock(<String>[
          'dartvel doctor           # host, tools and what each target can do',
          'dartvel inspect routes   # every route the generator found',
          'dartvel explain <code>   # what a diagnostic code means',
        ]),
      ],
    );

@DVFunctionalWidget()
Widget _honesty() => const Section(
      children: <Widget>[
        Eyebrow('BEFORE YOU DEPEND ON IT'),
        Heading('Check the status of each section you use.'),
        Bullets(<String>[
          'Sixteen sections are a frozen public contract with unfinished code '
              'behind them.',
          'Every section in spec-status.json says how much is built.',
        ]),
        Objection(
          'Is it production-ready?',
          'Parts of it. Dartvel is at 0.5.0, so check each section before '
              'you ship on it.',
        ),
        DVBox.wrapLine(<Widget>[
          PrimaryLink('Check what works today', '/features'),
          ExternalLink('Read spec-status.json', kSpecStatusUrl),
        ], spacing: 20, crossAlign: DVCrossAlign.center),
      ],
    );
