/// Studio, as routes of the application's own router.
///
/// Studio is not an application of its own. The generated router mounts
/// these routes at the Studio mount: `<mount>`, which the Studio grant
/// guards here on the client as the server guards it before anything is
/// rendered; `<mount>/login`, Studio's sign-in, which is for anybody; and
/// one route per screen, `<mount>/<screen>`, with the object half of an
/// address on top of it -- `<mount>/<screen>/<object>` -- for the screens
/// that can open one.
///
/// Studio's screens are a deferred library, and the sign-in another. Neither
/// is in `main.dart.js`, so a public page pays nothing for Studio; and the
/// screens' parts are loaded only after the guard let the caller through --
/// the server hands them to a granted session and to nobody else.
library;

import 'package:dartvel_core/dartvel.dart'
    show DVStudioScreenSpec, dvStudioScreens, dvStudioScreenAliases;
import 'package:dartvel_flutter/dartvel_flutter.dart'
    show DVPageScaffoldSpec, DVPageShell;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../routing/url_strategy.dart' show dvOpenUrl;
import 'studio_app_entry.dart' deferred as dartvel_studio;
import 'studio_host.dart';
import 'studio_server.dart'
    show DVStudioReply, DVStudioTransport, dvStudioBrowserTransport;
import 'studio_sign_in_entry.dart' deferred as dartvel_studio_sign_in;

/// Every id the mount answers a screen for.
///
/// A route per id rather than one route with `:screen` in it, because the
/// ids are known and finite: Studio's own list, which the server writes a
/// document for at every one of them, plus the two the server cannot know
/// about. A wildcard would answer `<mount>/anything` with a Studio screen
/// where the server answers it with a path nothing serves, and the two
/// halves of the address would disagree about which paths are Studio's.
final List<String> _studioScreenIds = <String>[
  for (final DVStudioScreenSpec screen in dvStudioScreens) screen.id,
  ...dvStudioScreenAliases.keys,
  // Declared by the project rather than by the server, which is why the
  // server never prints them: a screen only some builds have. The client
  // answers them anyway, because a build that declared one does have it.
  'flags',
  'operations',
];

/// Studio's routes at [mount] (`/__studio`), titled [title]: Studio, every
/// one of its screens, its sign-in and its first-run setup.
///
/// [transport] reaches Studio's API; the browser's, at `<mount>/api/`, by
/// default. [open] loads a path from the server as a page, which is how a
/// person who has just signed in reaches Studio: the server decides on the
/// grant again before it renders anything. [location] is the address a
/// Studio page was opened at; the browser's by default. [signInReturns] are
/// the other mounts Studio's grant guards, such as a documentation site with
/// `access: studio`, which the sign-in sends a person back to. [view] is the
/// application's `dartvelPagePreview`: each page as its route builds it,
/// which is how Studio's canvas draws a page exactly as the site does.
/// [splash] is the application's splash, drawn while Studio's code loads
/// and its grant is asked, where the first frame was an empty page.
List<RouteBase> dvStudioRoutes({
  required String mount,
  String title = 'Studio',
  DVStudioTransport? transport,
  void Function(String path)? open,
  Uri Function(GoRouterState state)? location,
  List<String> signInReturns = const <String>[],
  DVStudioPageView? view,
  DVStudioSplash? splash,
}) {
  // A transport and nothing more on this side of the deferred imports: an
  // object of Studio's made here would bring every method it has into
  // main.dart.js, and with them the code they reach. Each library makes its
  // own client from it.
  final DVStudioTransport send =
      transport ?? dvStudioBrowserTransport(base: '$mount/');
  final String login = '$mount/login';
  final String setup = '$mount/setup';

  // The Studio grant, asked on every visit rather than remembered: a grant
  // taken away is refused on the next navigation, not the next page load.
  // The server has already refused a stranger before this page existed; this
  // is the same guard for a navigation that never reached the server.
  Future<String?> guard(BuildContext context, GoRouterState state) async {
    if (await dvStudioGranted(send)) return null;
    return Uri(
      path: login,
      queryParameters: <String, String>{'from': state.uri.toString()},
    ).toString();
  }

  /// The screen named [id], with [object] open in it, as a page of the
  /// application: the same shell, the same look, and where the person is
  /// carried by the address, so Back, a reload and a pasted link all land in
  /// the same place.
  Page<void> screen(
    BuildContext context,
    GoRouterState state, {
    required String id,
    String? object,
  }) =>
      NoTransitionPage<void>(
        key: state.pageKey,
        // The application's page views and its look, taken here, under
        // the application's MaterialApp and above Studio's own frame.
        child: _dvStudioPage(
          child: DVStudioHost(
            view: view,
            look: DVStudioAppLook.capture(context),
            splash: splash,
            child: DVStudioDeferred(
              load: dartvel_studio.loadLibrary,
              splash: splash,
              builder: (BuildContext context) => dartvel_studio.dvStudioAppFor(
                transport: send,
                title: title,
                mount: mount,
                screen: dvStudioScreenAliases[id] ?? id,
                object: object,
                location: location?.call(state),
                open: open,
                // Navigated to, not pushed: the address bar follows the
                // screen as a history entry of its own, so Back walks back
                // through the screens and the objects a person opened, which
                // is what Back does in every tool Studio is measured against.
                onSelect: (String section, String? chosen) =>
                    _openStudio(router: GoRouter.of(context), mount: mount, section: section, object: chosen),
              ),
            ),
          ),
        ),
      );

  return <RouteBase>[
    GoRoute(
      path: mount,
      redirect: guard,
      pageBuilder: (BuildContext context, GoRouterState state) => screen(
        context,
        state,
        // The mount is Pages: `dvStudioTargetFor` names the same screen at
        // `<mount>` as at `<mount>/pages`, and so does this.
        id: _studioScreenIds.first,
      ),
    ),
    GoRoute(
      path: login,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          NoTransitionPage<void>(
            key: state.pageKey,
            child: _dvStudioPage(
              child: DVStudioDeferred(
                load: dartvel_studio_sign_in.loadLibrary,
                splash: splash,
                builder: (BuildContext context) =>
                    dartvel_studio_sign_in.dvStudioSignInFor(
                  transport: send,
                  mount: mount,
                  from: state.uri.queryParameters['from'],
                  title: title,
                  open: open ?? dvOpenUrl,
                  returns: signInReturns,
                ),
              ),
            ),
          ),
    ),
    // The first-run setup: the server sends every page of the mount here
    // until the owner has finished it, and answers this route only then.
    GoRoute(
      path: setup,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          NoTransitionPage<void>(
            key: state.pageKey,
            child: _dvStudioPage(
              child: DVStudioDeferred(
                load: dartvel_studio_sign_in.loadLibrary,
                splash: splash,
                builder: (BuildContext context) =>
                    dartvel_studio_sign_in.dvStudioSetupFor(
                  transport: send,
                  mount: mount,
                  title: title,
                  open: open ?? dvOpenUrl,
                ),
              ),
            ),
          ),
    ),
    // After the two above, which are literal paths and so win: `<mount>/login`
    // is a sign-in, not a screen that happens to be called "login", because
    // go_router matches the first route that fits.
    for (final String id in _studioScreenIds) ...<RouteBase>[
      GoRoute(
        path: '$mount/$id',
        redirect: guard,
        pageBuilder: (BuildContext context, GoRouterState state) =>
            screen(context, state, id: id),
      ),
      GoRoute(
        // The object half, which keeps its slashes: a page is at the route
        // it answers, so `<mount>/pages/shop/product` names that page. The
        // whole rest is one parameter rather than a `*splat`, because
        // go_router matches on the decoded path -- `Uri.path` of
        // `<mount>/pages/shop%2Fproduct` is `<mount>/pages/shop/product` --
        // so the encoded form the server prints and the literal form both
        // land here and name the same page.
        path: '$mount/$id/:object(.*)',
        redirect: guard,
        pageBuilder: (BuildContext context, GoRouterState state) => screen(
              context,
              state,
              id: id,
              object: state.pathParameters['object'],
            ),
      ),
    ],
  ];
}

/// Puts the address of a place in Studio on [router], which is what a
/// section reports when a person chooses something.
///
/// `<mount>/<section>`, with `<mount>/<section>/<object>` when there is one.
/// The object is a name a section gives the thing it has open -- a route, a
/// model, a function -- and it keeps its own slashes: a page is at its route,
/// `shop/product` under `pages` naming the page at `/shop/product`, which is
/// what the server prints and what the router's `:object(.*)` reads back.
///
/// A route carries a leading `/` that the address already has, so it is
/// dropped rather than doubled.
///
/// Navigated to, not pushed. go_router's `push` keeps the address to itself:
/// by default it does not report the new route to the browser, so the
/// location bar stayed on the screen a person started at, a reload opened
/// that screen again, and the link for the one they were looking at could not
/// be copied. `go` reports it, and the browser keeps each screen and object
/// as its own history entry, so Back walks back through them. Re-selecting
/// where they already are is left alone, so Back is not filled with the same
/// address twice.
void _openStudio({
  required GoRouter router,
  required String mount,
  required String section,
  String? object,
}) {
  // Keep a readable alias when navigating within the screen it names.
  final current = router.state.uri.path.substring(mount.length).split('/');
  final alias = current.length > 1 ? current[1] : '';
  if (dvStudioScreenAliases[alias] == section) section = alias;
  final String path = object == null
      ? '$mount/$section'
      : '$mount/$section/${object.replaceFirst(RegExp('^/+'), '')}';
  if (router.state.uri.path == path) return;
  router.go(path);
}

/// A Studio screen through the page shell every other page of the
/// application goes through, so Studio is not a second kind of page.
///
/// Without this Studio's route built straight to its own frame, and
/// everything the shell carries stopped at the router: Ctrl+F had no page
/// registered to match against and found nothing over Studio, a drag
/// selected nothing, and the keyboard arrows, a remote's D-pad and switch
/// control had nothing to move. Every one of those is inert until a page
/// declares it, so a Studio screen -- the screen a person spends their day
/// in -- had to be reachable by mouse alone.
///
/// [scaffold] off, because Studio draws its own chrome and a bar or a
/// Material scaffold above it would be a second one. [safeArea] off for the
/// same reason: Studio's sign-in and its first-run setup each draw their
/// own, and a safe area on the outside would inset everything Studio
/// measures against the screen edge a second time.
///
/// Selectable and findable, the default every page gets. The one place
/// that fights both is the canvas, where a drag moves an element and a
/// click selects one; that is inside a `DVPagePreviewScope`, which is what
/// the shell reads to stand down, and it did so before Studio had a shell
/// above it at all.
Widget _dvStudioPage({required Widget child}) => DVPageShell(
      spec: const DVPageScaffoldSpec(scaffold: false, safeArea: false),
      child: child,
    );

/// Whether the caller [send] speaks for may open Studio: `api/access`, and
/// no on anything but a clear yes.
Future<bool> dvStudioGranted(DVStudioTransport send) async {
  try {
    final DVStudioReply reply = await send('GET', 'api/access');
    final Object? body = reply.body;
    return reply.status == 200 && body is Map && body['granted'] == true;
  } on Object {
    return false;
  }
}

/// A Studio screen whose code is a deferred library: nothing until [load]
/// has fetched it, then [builder].
class DVStudioDeferred extends StatefulWidget {
  const DVStudioDeferred({
    super.key,
    required this.load,
    required this.builder,
    this.splash,
  });

  final Future<void> Function() load;
  final WidgetBuilder builder;

  /// Drawn while the code loads; an empty page without one.
  final DVStudioSplash? splash;

  @override
  State<DVStudioDeferred> createState() => _DVStudioDeferredState();
}

class _DVStudioDeferredState extends State<DVStudioDeferred> {
  // Asked each time rather than kept in a static: a loaded library answers
  // at once, and a future kept across widget tests is one whose zone is
  // gone.
  late final Future<void> _loaded = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _loaded,
    builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text(
            'Studio could not be loaded. Reload to try again.',
            textDirection: TextDirection.ltr,
          ),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        final DVStudioSplash? splash = widget.splash;
        return splash == null
            ? const SizedBox.expand()
            : DVStudioSplashView(splash);
      }
      return widget.builder(context);
    },
  );
}

/// Loads both of Studio's deferred libraries, for a widget test.
///
/// The VM loads a deferred library once per isolate and hands every later
/// caller the first load's future. A widget test runs each case on a fake
/// clock of its own, so a library first loaded inside one case never loads
/// for the next. Loaded here, from `setUpAll`, on the real clock, it is
/// already there for every case.
@visibleForTesting
Future<void> dvStudioLoadLibrariesForTest() async {
  await dartvel_studio.loadLibrary();
  await dartvel_studio_sign_in.loadLibrary();
}
