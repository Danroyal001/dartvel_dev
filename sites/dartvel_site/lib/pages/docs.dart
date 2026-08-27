import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

@DVPage(title: 'Documentation — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsPage(BuildContext context) => buildDocsPage(context);

Widget buildDocsPage(BuildContext context) => SitePage(
      current: '/docs',
      children: <Widget>[
        Section(
          children: <Widget>[
            const Eyebrow('DOCUMENTATION'),
            const Heading('From nothing to a running app.'),
            const Body(
              'Dartvel needs the Dart and Flutter SDKs to build an '
              'application. It does not need them to run the CLI: that is a '
              'single self-contained binary.',
              width: 640,
            ),
          ],
        ),
        _install(),
        _firstApp(),
        _pages(),
        _models(),
        _backend(),
        _signals(),
        _building(),
        _honesty(),
      ],
    );

Widget _install() => Section(
      tint: true,
      children: const <Widget>[
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

Widget _firstApp() => Section(
      children: const <Widget>[
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

Widget _pages() => Section(
      tint: true,
      children: const <Widget>[
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

Widget _models() => Section(
      children: const <Widget>[
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

Widget _backend() => Section(
      tint: true,
      children: const <Widget>[
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

Widget _signals() => Section(
      children: const <Widget>[
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

Widget _building() => Section(
      tint: true,
      children: const <Widget>[
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
      ],
    );

Widget _honesty() => Section(
      children: const <Widget>[
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
          'Fourteen sections are a frozen public contract with an unfinished '
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
