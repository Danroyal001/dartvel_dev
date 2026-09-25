// The whole generated client, compiled against the real API.
//
// Every other generator test reads the emitted text, and text that reads
// correctly still fails to compile. Four such defects shipped at once in
// models.g.dart, and separately every admin route generated a *private*
// DVRoutes member — the target existed and no application code could name it.
// Both classes of bug are invisible to string matching and obvious to the
// analyzer.
//
// So this generates a project the way `dartvel build` does — router, models,
// jobs, static paths, backend, and the admin pages — resolves it against the
// real dartvel_core and dartvel_flutter, and analyzes the lot.
//
// It costs a `flutter pub get`, which is why it lives in its own file: the
// rest of the generator tests stay instant.
@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/commands/admin_command.dart';
import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A model covering the field shapes that broke: nullable and non-nullable,
/// defaultable and not, a type with no sensible default, and a sensitive one.
// Flags declared the way an application declares them, and a page that reads
// them as a signal. The chain this proves compiles is the whole of it: the
// generator writes Flags, the barrel exports it, the runtime registers it, and
// context.flag(...) composes with another operand in a build method.
// The one declaration shape found to analyze without warnings. A private class
// nothing references draws unused_element, and its static const fields draw
// unused_field whatever pragma they carry; the class pragma clears the first,
// and a pragma'd member reading each flag clears the second. The
// specification's example omits both, so a project written from it warns on
// every flag — reported, rather than hidden here with ignore comments.
const String _flags = '''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
@pragma('vm:entry-point')
abstract class _Flags {
  /// The rewritten checkout.
  @DVFlag(owner: 'payments', expires: '2099-12-01')
  static const bool newCheckout = false;

  @DVFlag(owner: 'feed', expires: '2099-12-01')
  static const int pageSize = 20;

  @pragma('vm:entry-point')
  static List<Object?> get declared => <Object?>[newCheckout, pageSize];
}
''';

const String _checkoutPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Checkout')
@pragma('vm:entry-point')
Widget _checkoutPage(BuildContext context) => DVText(
      (context.flag(Flags.newCheckout) & true).value
          ? 'New checkout, \${Flags.pageSize.value} rows'
          : 'Checkout',
    );
''';

const String _model = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: DVSubject.self, retain: DVRetention.indefinite)
class _Account {
  final String id;
  final String email;
  final String? displayName;
  @DVModel.sensitiveField()
  final String passwordHash;
  final int seats;
  final double balance;
  final bool active;
  final DateTime createdAt;
  final DateTime? cancelledAt;

  const _Account({
    required this.id,
    required this.email,
    this.displayName,
    required this.passwordHash,
    required this.seats,
    required this.balance,
    required this.active,
    required this.createdAt,
    this.cancelledAt,
  });
}
''';

/// A model with a 3D asset field, whose generated viewer and page component
/// name widgets from dartvel_flutter and values from dartvel_core.
const String _product3d = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _Product {
  final String id;
  final String name;
  @DVModel.model3dField(poster: true, maxSizeMb: 25)
  final DVSceneAsset? asset;

  const _Product({required this.id, required this.name, this.asset});
}
''';

/// A model with a page by default, fields it protects -- a sensitive one and
/// the id of its privacy subject -- and a view policy written against the
/// generated client, so the page's policy questions compile against the
/// types an application actually has.
const String _article = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(subject: DVSubject.field('authorId'), retain: DVRetention.indefinite)
class const _Article({
  required final String slug,
  @DVModel.pageTitle() required final String title,
  @DVModel.mainContent() required final String body,
  required final bool published,
  required final String authorId,
  @DVModel.sensitiveField() required final String editorNotes,
});
''';

/// A person's record whose pages were asked for by name.
const String _member = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(
  generatePublicPages: true,
  subject: DVSubject.self,
  retain: DVRetention.indefinite,
)
class const _Member({required final String id, required final String name});
''';

const String _articlePolicy = '''
import 'package:dartvel_core/dartvel.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPolicy(Article)
class ArticlePolicy {
  bool view(DVSessionPrincipal? user, Article article) => article.published;

  bool viewSensitive(DVSessionPrincipal? user, Article article) =>
      user != null && user.userId == article.authorId;
}
''';

const String _indexLoading = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVFunctionalWidget()
Widget _indexPageLoading(BuildContext context) => const DVText('Loading');
''';

const String _indexError = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVFunctionalWidget()
Widget _indexPageError(BuildContext context) => const DVText('Sorry');
''';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

/// A nested, parameterised route — the shape whose typed target is generated
/// from the path.
const String _postPage = '''
import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Post')
@pragma('vm:entry-point')
Widget _postPage(BuildContext context) => const DVText('Post');
''';

/// A page that declares middleware, which emits a redirect and an installer
/// into the router.
///
/// Here rather than only in the string-matching tests because both of those
/// emissions are code: a call whose signature drifted, or an install naming
/// a symbol the barrel does not export, reads perfectly and does not
/// compile.
const String _guardedPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVUseMiddleware([DVMiddlewares.auth, DVMiddlewares.maintenance])
@DVPage(title: 'Account', mfa: DVMfa.recent(Duration(minutes: 15)))
@pragma('vm:entry-point')
Widget _accountPage(BuildContext context) => const DVText('Account');
''';

/// A tabs folder: the layout that builds the frame, a list and the detail
/// page pushed over it inside one tab, and a second tab.
const String _tabsLayout = '''
import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

class AppTabs extends DartvelTabsLayout {
  const AppTabs({super.key, required super.shell});

  static const List<DVRouteTarget> tabs = <DVRouteTarget>[
    DVRoutes.feed,
    DVRoutes.saved,
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: shell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: shell.goBranch,
      destinations: const <Widget>[
        NavigationDestination(icon: Icon(Icons.list), label: 'Feed'),
        NavigationDestination(icon: Icon(Icons.bookmark), label: 'Saved'),
      ],
    ),
  );
}
''';

String _tabPage(String name, String depth) => """
import 'package:flutter/widgets.dart';

import '${depth}dartvel_client/dartvel_client.dart';

@DVPage(title: '$name')
@pragma('vm:entry-point')
Widget _${name}Page(BuildContext context) =>
    DVNavLink(to: DVRoutes.feedPost(post: '1'), child: const DVText('$name'));
""";

/// Config routes beside the pages: every node type, a typed redirect to a
/// page's target, a typed link to a config route's, and an adopted GoRoute.
/// Analyzed with the rest, so the import, the spread and the targets the
/// generator writes for them are compiled rather than read.
const String _configRoutes = '''
import 'package:flutter/widgets.dart';

import 'dartvel_client/dartvel_client.dart';

final List<DVRouteNode> routes = <DVRouteNode>[
  DVRoute(
    path: '/settings',
    title: 'Settings',
    builder: (BuildContext context, DVRouteState state) =>
        DVNavLink(to: DVRoutes.order(id: '42'), child: const DVText('Order')),
  ),
  DVRoute(
    path: '/orders',
    builder: (BuildContext context, DVRouteState state) =>
        const DVText('Orders'),
    routes: <DVRouteNode>[
      DVRoute(
        path: ':id',
        name: 'order',
        builder: (BuildContext context, DVRouteState state) =>
            DVText(state.params['id'] ?? ''),
      ),
    ],
  ),
  DVShellRoute(
    redirect: (BuildContext context, DVRouteState state) async =>
        DV.Auth.currentUser == null ? DVRoutes.index : null,
    builder: (BuildContext context, DVRouteState state, Widget child) => child,
    routes: <DVRouteNode>[
      DVRoute(
        path: '/reports',
        builder: (BuildContext context, DVRouteState state) =>
            const DVText('Reports'),
      ),
    ],
  ),
  DVStatefulShellRoute(
    builder:
        (BuildContext context, DVRouteState state, DVShellNavigation shell) =>
            shell,
    branches: <DVShellBranch>[
      DVShellBranch(
        initialLocation: DVRoutes.stream,
        routes: <DVRouteNode>[
          DVRoute(
            path: '/stream',
            builder: (BuildContext context, DVRouteState state) =>
                const DVText('Stream'),
          ),
        ],
      ),
    ],
  ),
  DVGoRoutes(<RouteBase>[
    GoRoute(
      path: '/legacy',
      builder: (BuildContext context, GoRouterState state) =>
          const DVText('Legacy'),
    ),
  ]),
];
''';

const String _backendFunction = '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(mfa: DVMfa.required)
@pragma('vm:entry-point')
Future<Map<String, Object?>> _ping() async => <String, Object?>{'ok': true};
''';

/// The monorepo root, resolved from this package rather than the working
/// directory — several suites here move it.
Future<String> repoRoot() async {
  final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'));
  if (lib == null) {
    throw StateError('dartvel_cli could not resolve its own package URI.');
  }
  return p.normalize(p.join(p.dirname(lib.toFilePath()), '..', '..', '..'));
}

void write(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void main() {
  late Directory project;
  late ProcessResult analysis;

  setUpAll(() async {
    final root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_analyze_');

    // The analyzer settings a real project gets, so the fixture is judged
    // the way `dartvel create` judges what it wrote.
    write(p.join(project.path, 'analysis_options.yaml'),
        ProjectTemplates.analysisOptionsTemplate);
    write(p.join(project.path, 'lib', 'models', 'account.dart'), _model);
    write(p.join(project.path, 'lib', 'models', 'product.dart'), _product3d);
    write(p.join(project.path, 'lib', 'models', 'article.dart'), _article);
    write(p.join(project.path, 'lib', 'models', 'member.dart'), _member);
    write(p.join(project.path, 'lib', 'policies', 'article_policy.dart'),
        _articlePolicy);
    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _indexPage);
    write(p.join(project.path, 'lib', 'pages', 'index.loading.dart'),
        _indexLoading);
    write(p.join(project.path, 'lib', 'pages', 'index.error.dart'),
        _indexError);
    write(p.join(project.path, 'lib', 'pages', 'posts', '[slug].page.dart'),
        _postPage);
    write(p.join(project.path, 'lib', 'pages', 'account.page.dart'),
        _guardedPage);
    write(p.join(project.path, 'lib', 'backend', 'ping.dart'), _backendFunction);
    write(p.join(project.path, 'lib', 'routes.dart'), _configRoutes);
    write(p.join(project.path, 'lib', 'pages', '(tabs)', '_layout.dart'),
        _tabsLayout);
    write(p.join(project.path, 'lib', 'pages', '(tabs)', 'feed', 'index.page.dart'),
        _tabPage('feed', '../../../'));
    write(p.join(project.path, 'lib', 'pages', '(tabs)', 'feed', '[post].page.dart'),
        _tabPage('feedPost', '../../../'));
    write(p.join(project.path, 'lib', 'pages', '(tabs)', 'saved.page.dart'),
        _tabPage('saved', '../../'));
    write(p.join(project.path, 'lib', 'flags', 'flags.dart'), _flags);
    write(p.join(project.path, 'lib', 'pages', 'checkout.page.dart'),
        _checkoutPage);
    // A policy for the platform API's scope to name, so the scope registry
    // and the OAuth consent route are generated and analyzed too.
    write(p.join(project.path, 'lib', 'policies', 'account_policy.dart'), '''
import 'package:dartvel_core/dartvel.dart';

class AccountRecord {
  const AccountRecord();
}

@DVPolicy(AccountRecord)
class AccountRecordPolicy {
  bool view(Object? user, AccountRecord account) => true;
}
''');
    write(p.join(project.path, 'pubspec.yaml'), '''
name: generated_client_probe
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
dartvel:
  prodBackendHost: https://example.com
  platformApi:
    scopes:
      accounts:read:
        actions: [AccountRecord.view]
        description: See your account
    oauth: true
  memory:
    budget: 64MB
    segment: 16MB
    touchPages: desktop
    targets:
      tizen: { budget: 32MB, segment: 8MB }
  deviceProfiles:
    lobby:
      platform: sony-elinux
      ram: 1GB
      memory: { budget: 16MB }
''');
    // The Dartvel packages declare hosted constraints on each other so they
    // can be published; pub refuses a path dependency in a published package.
    // A probe that depends on them by path therefore has to override the whole
    // set, or pub reports the two kinds as irreconcilable:
    // "dartvel_flutter from path depends on dartvel_core from hosted and
    // generated_client_probe depends on dartvel_core from path".
    write(p.join(project.path, 'pubspec_overrides.yaml'), '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
''');

    // Admin pages first: they are ordinary pages, so the router has to see
    // them. Generating them afterwards leaves their routes out of DVRoutes
    // entirely, which is also how a bug in route naming went unnoticed.
    //
    // The project is handed over rather than made the working directory,
    // which is one value shared by every suite running beside this one.
    DartvelAdminGenerator.generate(root: project, force: true);
    await routes.generate(root_: project.path);

    final resolved = await Process.run('flutter', <String>['pub', 'get'],
        workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
    analysis = await Process.run(
      'flutter',
      <String>['analyze', 'lib'],
      workingDirectory: project.path,
    );
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  List<String> linesContaining(String marker) => const LineSplitter()
      .convert('${analysis.stdout}${analysis.stderr}')
      .where((String line) => line.contains(marker))
      // The annotated inputs are private by design and referenced only by the
      // generated code, so the analyzer's unused-element warnings about them
      // are the rule working, not a defect.
      .where((String line) => !line.contains('lib/models/account.dart'))
      .where((String line) => !line.contains('lib/models/product.dart'))
      .where((String line) => !line.contains('lib/models/article.dart'))
      .where((String line) => !line.contains('lib/models/member.dart'))
      .where((String line) => !line.contains('lib/backend/'))
      .where((String line) => !line.contains('.page.dart'))
      .toList(growable: false);

  test('the generated project has no analyzer errors', () {
    final errors = linesContaining('error •');

    expect(errors, isEmpty,
        reason: 'the generated project must compile:\n${errors.join('\n')}');
  });

  test('the generated project has no analyzer warnings', () {
    // Warnings are not style here. `String??` parsed as a warning cascade, and
    // the private DVRoutes members showed up as unused_field — which is how a
    // route nobody could navigate to would be caught.
    final warnings = linesContaining('warning •');

    expect(warnings, isEmpty,
        reason: 'the generated project must be warning-clean:\n'
            '${warnings.join('\n')}');
  });

  test('every generated file was actually produced', () {
    // A pass because nothing was generated would be worse than a failure.
    final client = Directory(p.join(project.path, 'lib', 'dartvel_client'));
    final produced = client
        .listSync()
        .whereType<File>()
        .map((File f) => p.basename(f.path))
        .toSet();

    expect(produced, containsAll(<String>[
      'models.g.dart',
      'router.g.dart',
      'widgets.g.dart',
      'functions.g.dart',
      'jobs.g.dart',
      'client_jobs.g.dart',
      'dartvel_client.dart',
    ]));
    expect(analysis.exitCode, anyOf(0, 1),
        reason: 'flutter analyze did not run: ${analysis.stderr}');
  });

  test('a functional loading and error companion are the ones rendered', () {
    final String router = File(
      p.join(project.path, 'lib', 'dartvel_client', 'router.g.dart'),
    ).readAsStringSync();

    expect(router, contains('IndexPageLoading()'));
    expect(router, contains('IndexPageError()'));
    // Named through the client, where a functional widget's class is
    // generated, rather than through the page file, which has no class.
    expect(router, isNot(matches(RegExp(r'p[le]\\d+\\.IndexPage(Loading|Error)'))));
  });

  test('the middleware fixture is actually in the analyzed router', () {
    // Without this the guarded page could stop being picked up -- renamed
    // convention, moved directory -- and the analyzer would keep passing on
    // a router that no longer contains the code this fixture exists to
    // compile. A green suite proving nothing is the failure worth guarding.
    final String router = File(
      p.join(project.path, 'lib', 'dartvel_client', 'router.g.dart'),
    ).readAsStringSync();

    expect(router, contains('DVPageMiddleware.check'));
    expect(router, contains('DVPageMiddleware.isSignedIn ??='));
  });

  test('the config routes are mounted in the analyzed router', () {
    // Without this the routes file could stop being read and the analyzer
    // would keep passing on a router with no config routes in it.
    final String router = File(
      p.join(project.path, 'lib', 'dartvel_client', 'router.g.dart'),
    ).readAsStringSync();

    expect(router, contains('dv_config.routes,'));
    expect(router, contains("static DVRouteTarget order({required String id})"));
    expect(router, contains('dvShellNavigation(shell)'));
    expect(router, contains('List<RouteBase> dartvelRoutes('));
    expect(router, contains('final router = DVRouter('));
  });

  test('the second-factor gate, its challenge route and the step-up are in '
      'the analyzed client', () {
    // The Account page declares mfa: and the backend function does too, so
    // the redirect, the /second-factor route, the step-up install and the
    // call through DVStepUp are code the analyzer compiled -- a helper whose
    // signature drifted reads perfectly as text.
    final String client = Directory(
      p.join(project.path, 'lib', 'dartvel_client'),
    )
        .listSync()
        .whereType<File>()
        .map((File f) => f.readAsStringSync())
        .join('\n');
    expect(client,
        contains('DVPageMfa.recent(context, state, const Duration(milliseconds: 900000))'));
    expect(client, contains("path: '/second-factor'"));
    expect(client, contains('DVAuth.installStepUp();'));
    expect(client, contains('DVStepUp.send('));
  });

  test('the account page routes, their entries and the account mail are in '
      'the analyzed client', () {
    final String client = Directory(
      p.join(project.path, 'lib', 'dartvel_client'),
    )
        .listSync()
        .whereType<File>()
        .map((File f) => f.readAsStringSync())
        .join('\n');
    expect(client,
        contains('DVAccountPages.requireSession(context, state)'));
    expect(client, contains('DV.Auth.SecurityPage()'));
    expect(client, contains('const List<DVAccountPageEntry> dartvelAccountPages'));
    expect(client, contains('DVMailMessage dartvelEmailVerificationMail('));
  });

  test('the memory configuration is actually in the analyzed client', () {
    // The fixture declares dartvel.memory so the analyzer sees the startup
    // call and the names it imports. Without this check the call could stop
    // being emitted and the analysis would still pass.
    final String client = Directory(
      p.join(project.path, 'lib', 'dartvel_client'),
    )
        .listSync()
        .whereType<File>()
        .map((File f) => f.readAsStringSync())
        .join('\n');

    expect(client, contains('DVMemory.configure(DVMemoryConfig.parse('));
    expect(client, contains("'lobby'"));
  });

  test('a 3D model field and its viewer are in the analyzed client', () {
    // Without this the two assertions above could pass on a client that
    // never generated the viewer at all.
    final String models = File(
      p.join(project.path, 'lib', 'dartvel_client', 'models.g.dart'),
    ).readAsStringSync();
    expect(models, contains('Widget viewer3D() => DVModel3DViewer(asset);'));
    expect(models, contains('DVModel3DViewer(model.asset)'));
  });

  test('a default model page and its policy questions are in the analyzed '
      'client', () {
    final String models = File(p.join(
            project.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
    expect(models, contains('static Widget publicPage(String slug)'));
    expect(models, contains("mayViewProtected('Article', viewer, found)"));
    expect(models, contains('static Widget _dvProtectedPageFields(Article'));
    expect(models, contains('static Widget publicPage(String id)'));
    final String router = File(p.join(
            project.path, 'lib', 'dartvel_client', 'router.g.dart'))
        .readAsStringSync();
    expect(router, contains("path: '/articles/:slug'"));
    expect(router, contains("path: '/members/:id'"));
  });

  test('the admin pages were generated and analyzed too', () {
    final admin =
        Directory(p.join(project.path, 'lib', 'pages', '_dartvel_admin'));

    expect(admin.existsSync(), isTrue);
    expect(
      admin.listSync().whereType<File>().map((File f) => p.basename(f.path)),
      containsAll(<String>[
        'index.page.dart',
        'models.page.dart',
        'queues.page.dart',
        'cache.page.dart',
        'routes.page.dart',
        'studio.page.dart',
        'outbox.page.dart',
        'policies.page.dart',
        'telemetry.page.dart',
      ]),
    );
  });

  test('a page reaches DV.Cache through the barrel, and not its machinery',
      () async {
    // dartvel.cache sets the default store and DV.Cache.withAdapter switches
    // store in code, so the adapters are the application's. The Redis
    // client, the tag registry, the config reader and DVCacheRuntime are the
    // framework's. Outside lib/, so the analysis above is untouched by it.
    write(p.join(project.path, 'probe', 'cache_surface.dart'), '''
import 'package:generated_client_probe/dartvel_client/dartvel_client.dart';

Future<void> control() async {
  await DV.Cache.set('k', 1, ttl: const Duration(minutes: 1));
  final DVCacheView switched = DV.Cache.withAdapter(DVMemoryCacheAdapter());
  await switched.delete(all: true);
}

List<Type> get adapters => <Type>[
      DVCacheAdapter,
      DVMemoryCacheAdapter,
      DVDatabaseCacheAdapter,
      DVRedisCacheAdapter,
      DVMemcachedCacheAdapter,
      DVDistributedCacheAdapter,
    ];

List<Type> get machinery => <Type>[
      DVRedisClient,
      DVCacheTags,
      DVCacheConfig,
      DVCacheRuntime,
    ];
''');
    final ProcessResult probe = await Process.run(
      'flutter',
      <String>['analyze', '--no-fatal-infos', 'probe/cache_surface.dart'],
      workingDirectory: project.path,
    );
    final String output = '${probe.stdout}${probe.stderr}';
    final List<String> undefined = const LineSplitter()
        .convert(output)
        .where((String l) => l.contains('undefined_identifier'))
        .toList();
    expect(undefined, hasLength(4), reason: output);
    // The control: DV.Cache and the adapters resolve, so the four are hidden
    // rather than the probe failing to resolve at all.
    expect(output, isNot(contains("isn't defined for the type 'DV'")));
    expect(output, isNot(contains('uri_does_not_exist')));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
