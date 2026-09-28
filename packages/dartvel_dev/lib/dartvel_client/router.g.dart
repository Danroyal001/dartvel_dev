// GENERATED – do not edit.
// ignore_for_file: unnecessary_import, unused_import, prefer_const_constructors
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'config.g.dart';
import 'dartvel_config.g.dart';
import 'dartvel_runtime.dart';
import 'env.g.dart';
import 'functions.g.dart';
import 'models.g.dart';
import 'widgets.g.dart';

const _defaultSeo = SeoProps(
  siteName: '',
  title: '',
  description: '',
  imageUrl: '',
  twitterHandle: '',
);

const _projectDefaultTransition = PageTransitionSpec(
  type: DvTransition.fade,
  duration: Duration(milliseconds: 220),
  curve: Curves.easeInOut,
);

String? _globalRedirect(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  final kioskRoute = dvKioskRouteRedirect(path);
  if (kioskRoute != null) return kioskRoute;
  if (path == '/index.html') return '/';
  if (path.endsWith('/index.html')) {
    return state.uri.replace(path: path.substring(0, path.length - 'index.html'.length - 1)).toString();
  }
  if (path.length > 1 && path.endsWith('/')) {
    final newUri = state.uri.replace(path: path.substring(0, path.length - 1));
    return newUri.toString();
  }
  return null;
}




/// Creates the GoRouter instance for Dartvel routing.
/// The page routes this router refuses without a guard passing.
///
/// Read by the build to keep private routes out of sitemap.xml, and
/// available to an application that wants to hide a link it would not be
/// allowed to follow.
const List<String> dartvelGuardedRoutes = <String>[
  '/account/profile',
  '/account/security',
  '/account/sessions',
  '/account/delete',
];

/// The prebuilt account pages this application serves, where
/// `dartvel.auth.pages` put them, for its own navigation.
///
/// `DVAccountPages.visible(dartvelAccountPages, signedIn: ...)` is what a
/// menu offers: a signed-out person is not offered a page that only sends
/// them to sign in.
const List<DVAccountPageEntry> dartvelAccountPages = <DVAccountPageEntry>[
  DVAccountPageEntry(DVAccountPage.profile, DVRouteTarget('/account/profile')),
  DVAccountPageEntry(DVAccountPage.security, DVRouteTarget('/account/security')),
  DVAccountPageEntry(DVAccountPage.sessions, DVRouteTarget('/account/sessions')),
  DVAccountPageEntry(DVAccountPage.delete, DVRouteTarget('/account/delete')),
  DVAccountPageEntry(DVAccountPage.signUp, DVRouteTarget('/sign-up')),
  DVAccountPageEntry(DVAccountPage.signIn, DVRouteTarget('/login')),
];

/// What each page's `@DVPage(sitemap: ...)` said about how it should be
/// crawled, by route.
///
/// Read by the build that writes sitemap.xml. A route that is not here said
/// nothing, and takes the project's defaults.
const Map<String, DVPageSitemap> dartvelSitemapEntries = <String, DVPageSitemap>{};

/// What the routes need before the first one is built, whichever router
/// they end up in.
void _dartvelSetUp(List<String> arguments) {
  configureDartvelRuntime(arguments: arguments);
  // What each route can fetch and show before you go there, so DVNavLink can
  // preload a destination on hover and preview it on a rest. The link cannot
  // know how to build a route; the router does.


  dvSignInRoute = '/login';
  dvEnsureSemantics();

}

/// Every route this application serves, in one list ordered so a static
/// route is matched before a parameter route that would hide it, whichever
/// source either came from.
List<RouteBase> _dartvelRouteList() => dvOrderGoRoutes(<RouteBase>[
    GoRoute(
      path: '/account/profile',
      redirect: (context, state) => DVAccountPages.requireSession(context, state),
      pageBuilder: (context, state) => NoTransitionPage<void>(
        child: Scaffold(body: SafeArea(child: DV.Auth.ProfilePage())),
      ),
    ),
    GoRoute(
      path: '/account/security',
      redirect: (context, state) => DVAccountPages.requireSession(context, state),
      pageBuilder: (context, state) => NoTransitionPage<void>(
        child: Scaffold(body: SafeArea(child: DV.Auth.SecurityPage())),
      ),
    ),
    GoRoute(
      path: '/account/sessions',
      redirect: (context, state) => DVAccountPages.requireSession(context, state),
      pageBuilder: (context, state) => NoTransitionPage<void>(
        child: Scaffold(body: SafeArea(child: DV.Auth.SessionsPage())),
      ),
    ),
    GoRoute(
      path: '/account/delete',
      redirect: (context, state) => DVAccountPages.requireSession(context, state),
      pageBuilder: (context, state) => NoTransitionPage<void>(
        child: Scaffold(body: SafeArea(child: DV.Auth.DeletePage())),
      ),
    ),
    GoRoute(
      path: '/sign-up',
      pageBuilder: (context, state) => NoTransitionPage<void>(
        child: Scaffold(body: SafeArea(child: DV.Auth.SignUpPage())),
      ),
    ),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => NoTransitionPage<void>(
        child: Scaffold(body: SafeArea(child: DV.Auth.SignInWithEmailAndPasswordPage(from: state.uri.queryParameters['from']))),
      ),
    ),
    ]);

/// This application's routes, for an application that keeps its own
/// GoRouter: `GoRouter(routes: [...hostRoutes, ...dartvelRoutes(at: '/app')])`,
/// then `DVNavigation.attach(router)`.
///
/// [at] is `/` to sit beside the host's routes, or a prefix to sit under.
/// DV.Navigation places Dartvel's targets under it and leaves the host's
/// paths alone. The host's router keeps its own top-level redirect, error
/// page and URL strategy; the ones createDartvelRouter sets are not applied.
List<RouteBase> dartvelRoutes({String at = '/', List<String> arguments = const <String>[]}) {
  _dartvelSetUp(arguments);
  return dvMountRoutes(_dartvelRouteList(), at: at);
}

GoRouter createDartvelRouter({List<String> arguments = const <String>[]}) {
  _dartvelSetUp(arguments);
  // This application owns the router, so nothing is mounted under a prefix.
  dvResetMount();
  // Path URLs on the web, not the hash Flutter defaults to.
  //
  // Without this, /docs never reaches the router: the browser asks for the
  // page, the app boots, and the router sees only "/" -- so every deep link
  // renders the home page and every URL grows a #. For a site that is fatal
  // rather than untidy, because a crawler indexes /#/docs as /, and a shared
  // link opens the wrong page.
  //
  // It needs the server to serve index.html for unknown paths, which is what
  // the .htaccess and dartvel deploy configuration do.
  dvUsePathUrlStrategy();
  // A DVRouter rather than a GoRouter: while the first location's guards
  // are still deciding, it paints a pending view where go_router paints
  // nothing, so a deep link onto a guarded page is never a blank screen.
  final router = DVRouter(
    routes: _dartvelRouteList(),
    redirect: _globalRedirect,
    // A route with no compiled page may still be a Studio page: builder
    // documents are data, so saving one publishes it without a rebuild.
    // Compiled routes always win — the store is only consulted here, after
    // matching has already failed.
    // A route with no compiled page at all may still be a Studio page.
    errorBuilder: (BuildContext context, GoRouterState state) =>
        DVStudioPageRoute(state.uri.path),
  );
  // DV.Navigation is used from callbacks with no BuildContext, so it needs the
  // live router rather than looking one up from the widget tree.
  DVNavigation.attach(router);

  // Anchors in the semantics tree are real anchors -- what a crawler follows
  // and what a screen reader announces -- and also what the browser navigates
  // natively, tearing the document down and rebuilding the whole application
  // to move between two routes. Intercepted so an in-app link pushes the
  // route instead. Anything that is not an in-app link is left to the
  // browser, which is the only correct default.
  dvInterceptLinkNavigation(router.go);

  // Without this DVLinkOpener has no implementation, so DVNavLink.external
  // and every middle-click silently do nothing -- which looks exactly like a
  // link that works.
  DVLinkOpener.install(dvOpenUrl,
      browserFollowsAnchors: dvBrowserFollowsAnchors);
  return router;
}

/// Strongly typed route targets for type-safe navigation.
class DVRoutes {
}

/// Every generated route, for tools that need to
/// enumerate them rather than navigate to one.
const List<DVRouteInfo> dartvelRouteManifest = <DVRouteInfo>[
];

