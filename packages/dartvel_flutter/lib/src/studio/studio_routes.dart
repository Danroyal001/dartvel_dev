/// Studio, as routes of the application's own router.
///
/// Studio is not an application of its own. The generated router mounts
/// these routes at the Studio mount: `<mount>`, which the Studio grant
/// guards here on the client as the server guards it before anything is
/// rendered, and `<mount>/login`, Studio's sign-in, which is for anybody.
///
/// Studio's screens are a deferred library, and the sign-in another. Neither
/// is in `main.dart.js`, so a public page pays nothing for Studio; and the
/// screens' parts are loaded only after the guard let the caller through --
/// the server hands them to a granted session and to nobody else.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../routing/url_strategy.dart' show dvOpenUrl;
import 'studio_app_entry.dart' deferred as dartvel_studio;
import 'studio_server.dart'
    show DVStudioReply, DVStudioTransport, dvStudioBrowserTransport;
import 'studio_sign_in_entry.dart' deferred as dartvel_studio_sign_in;

/// Studio's routes at [mount] (`/__studio`), titled [title]: Studio, its
/// sign-in and its first-run setup.
///
/// [transport] reaches Studio's API; the browser's, at `<mount>/api/`, by
/// default. [open] loads a path from the server as a page, which is how a
/// person who has just signed in reaches Studio: the server decides on the
/// grant again before it renders anything. [location] is the address a
/// Studio page was opened at; the browser's by default. [signInReturns] are
/// the other mounts Studio's grant guards, such as a documentation site with
/// `access: studio`, which the sign-in sends a person back to.
List<RouteBase> dvStudioRoutes({
  required String mount,
  String title = 'Studio',
  DVStudioTransport? transport,
  void Function(String path)? open,
  Uri Function(GoRouterState state)? location,
  List<String> signInReturns = const <String>[],
}) {
  // A transport and nothing more on this side of the deferred imports: an
  // object of Studio's made here would bring every method it has into
  // main.dart.js, and with them the code they reach. Each library makes its
  // own client from it.
  final DVStudioTransport send =
      transport ?? dvStudioBrowserTransport(base: '$mount/');
  final String login = '$mount/login';
  final String setup = '$mount/setup';
  return <RouteBase>[
    GoRoute(
      path: mount,
      // The Studio grant, asked on every visit rather than remembered: a
      // grant taken away is refused on the next navigation, not the next
      // page load. The server has already refused a stranger before this
      // page existed; this is the same guard for a navigation that never
      // reached the server.
      redirect: (BuildContext context, GoRouterState state) async {
        if (await dvStudioGranted(send)) return null;
        return Uri(
          path: login,
          queryParameters: <String, String>{'from': state.uri.toString()},
        ).toString();
      },
      pageBuilder: (BuildContext context, GoRouterState state) =>
          NoTransitionPage<void>(
            key: state.pageKey,
            child: DVStudioDeferred(
              load: dartvel_studio.loadLibrary,
              builder: (BuildContext context) => dartvel_studio.dvStudioAppFor(
                transport: send,
                title: title,
                location: location?.call(state),
                open: open,
              ),
            ),
          ),
    ),
    GoRoute(
      path: login,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          NoTransitionPage<void>(
            key: state.pageKey,
            child: DVStudioDeferred(
              load: dartvel_studio_sign_in.loadLibrary,
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
    // The first-run setup: the server sends every page of the mount here
    // until the owner has finished it, and answers this route only then.
    GoRoute(
      path: setup,
      pageBuilder: (BuildContext context, GoRouterState state) =>
          NoTransitionPage<void>(
            key: state.pageKey,
            child: DVStudioDeferred(
              load: dartvel_studio_sign_in.loadLibrary,
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
  ];
}

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
  });

  final Future<void> Function() load;
  final WidgetBuilder builder;

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
        return const SizedBox.expand();
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
