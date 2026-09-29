/// The documentation site: the application that draws what `dartvel docs`
/// writes.
///
/// It was nine pages of HTML and a stylesheet, authored by hand inside a build
/// step, with a second name for every page the graph already had and an
/// `<a href>` for every link. It is one app now, compiled the way
/// `dartvel build studio` compiles Studio's, and every page it shows is drawn
/// from the document beside it.
///
/// One route carries the whole site rather than one route per page, and the
/// page a path names is decided here rather than by a router: a build writes a
/// document and cannot know what the application has since added, so the site
/// that reads the document has to answer for a path no page has. That is the
/// application's own not-found page, which is the one thing here that is not
/// the documentation being wrong about itself.
///
/// So the routing is one `/:rest(.*)`, whose builder sees the whole URI: path,
/// query and the anchor after the `#`, all of which arrive in an address
/// somebody typed or followed. A link to a row in a table therefore carries a
/// real anchor, and arriving at one scrolls to the row rather than to the top
/// of a page the reader then has to search.
library dartvel_flutter.docs.app;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart'
    show DVDocsBlock, DVDocsDocument, DVDocsPage, DVDocsTarget;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../dartvel_flutter.dart' show DVNavigation, DVRouteTarget;
import '../routing/nav_link.dart'
    show DVLinkOpener, DVLinkPreload, DVLinkPreview, DVNavLink;
import '../routing/page_errors.dart' show DVNotFoundPage;
import '../routing/router.dart' show DVRoutePending, DVRouter;
import '../routing/url_strategy.dart' show dvBrowserFollowsAnchors, dvOpenUrl;
import 'docs_blocks.dart';
import 'docs_source.dart';
import 'docs_style.dart';

/// The documentation site.
///
/// [document] is what to draw, and is the whole of what the app needs: a test
/// hands it one, and the compiled site fetches its own through [source].
///
/// [source] reads it when there is no document to hand, which is also how an
/// application embedding the documentation points at a payload of its own. It
/// is read once, at startup, and a failure is shown as itself rather than as
/// an empty site: the commonest cause is a directory still serving the pages
/// this replaced, and "empty documentation" sends whoever is looking for the
/// cause somewhere else.
///
/// [base] is where the site is mounted, for the browser's own reader;
/// [location] is the address it was opened at, the browser's by default;
/// [open] is the app's own way out for a link that leaves the site.
class DVDocsApp extends StatefulWidget {
  const DVDocsApp({
    super.key,
    this.document,
    this.source,
    this.base = '/',
    this.title,
    this.location,
    this.open,
  });

  final DVDocsDocument? document;

  /// Where the document comes from, when it is not handed in.
  final DVDocsSource? source;

  /// Where the site is mounted, for the browser's own reader.
  final String base;

  /// The document title. The application's name by default.
  final String? title;

  /// The address the app was opened at; the browser's by default.
  final Uri? location;

  /// Opens a destination that leaves the site, where the platform has no way
  /// of its own to answer with.
  final void Function(String url)? open;

  @override
  State<DVDocsApp> createState() => _DVDocsAppState();
}

class _DVDocsAppState extends State<DVDocsApp> {
  DVDocsDocument? _document;
  Object? _failure;
  DVRouter? _router;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    if (document != null) {
      _adopt(document);
    } else {
      unawaited(_read());
    }
  }

  @override
  void didUpdateWidget(covariant DVDocsApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    final document = widget.document;
    if (document != null && !identical(document, _document)) {
      _adopt(document);
    } else if (widget.source != oldWidget.source) {
      unawaited(_read());
    }
    // The address is the page, so a different address is a different page --
    // with the router left alone. Swapping a router for a new location throws
    // away the scroll offset, the focus and the history with it, which is what
    // a full page load does and is the reason there is a router.
    final DVRouter? router = _router;
    if (router != null && widget.location != oldWidget.location) {
      router.go(_where());
    }
    if (mounted) setState(() {});
  }

  /// The address the app is at, which is the address the site is at.
  ///
  /// [DVDocsApp.location] where a caller named one -- a test, a server handing
  /// the site a path, an application mounting it under a prefix -- and the
  /// browser's own where there is a browser. A native process has no address
  /// to read, and `Uri.base` is the path of the program rather than a page, so
  /// it opens at the mount instead of answering "not found" for a directory.
  Uri get _here =>
      widget.location ??
      (kIsWeb ? Uri.base : Uri(path: widget.base.endsWith('/') ? widget.base : '${widget.base}/'));

  /// The address as a router location: path, query and anchor.
  ///
  /// All three, because all three arrive in an address somebody typed. The
  /// anchor is the difference between a link to a row and a link to the top of
  /// the page the row is in.
  String _where() {
    final Uri uri = _here;
    final String path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.hasQuery ? '$path?${uri.query}' : path}'
        '${uri.fragment.isEmpty ? '' : '#${uri.fragment}'}';
  }

  Future<void> _read() async {
    try {
      final DVDocsDocument document = await (widget.source ??
              dvDocsBrowserSource(base: widget.base))();
      if (!mounted) return;
      _adopt(document);
      setState(() {});
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error;
        _document = null;
      });
    }
  }

  void _adopt(DVDocsDocument document) {
    _document = document;
    _failure = null;
    if (_router != null) return;
    final DVRouter router = DVRouter(
      initialLocation: _where(),
      routes: <RouteBase>[
        GoRoute(
          // Everything. A bare `/*` does not match at the top level, which is
          // why this is a path parameter with a pattern rather than a
          // wildcard: the site answers for every address it is opened at,
          // including `/`.
          path: '/:rest(.*)',
          builder: (BuildContext context, GoRouterState state) => _at(state.uri),
        ),
      ],
    );
    // One router for the life of the app: links navigate in it, and
    // `DVNavLink` asks it where a target is before it will draw a destination.
    DVNavigation.attach(router);
    final void Function(String url)? open = widget.open;
    DVLinkOpener.install(
      // A caller's own way out takes a destination rather than an intention:
      // opening beside this page is the platform's business, and on the web
      // the platform is the one that knows how to do it.
      open == null
          ? dvOpenUrl
          : (String path, {bool newTab = false}) => open(path),
      browserFollowsAnchors: dvBrowserFollowsAnchors,
    );
    _router = router;
  }

  /// The page the address names, or the site's own not-found page.
  Widget _at(Uri uri) {
    final DVDocsDocument? document = _document;
    if (document == null) return const DVRoutePending();
    return DVDocsSite(
      document: document,
      path: uri.path,
      fragment: uri.fragment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DVRouter? router = _router;
    if (router == null) return _beforeDocument();
    return MaterialApp.router(
      title: widget.title ?? _document!.application,
      debugShowCheckedModeBanner: false,
      theme: dvDocsTheme(.light),
      darkTheme: dvDocsTheme(.dark),
      routerConfig: router,
    );
  }

  /// What the app shows with no document to draw.
  ///
  /// The loading bar the framework shows for a route whose data has not
  /// arrived, because that is what this is: a route whose document has not been
  /// read. The site's own frame around an empty page would be a page with a
  /// title, a navigation and nothing under it, which reads as wrong rather
  /// than as unfinished.
  Widget _beforeDocument() {
    final Object? failure = _failure;
    if (failure == null) return const MaterialApp(home: DVRoutePending());
    return MaterialApp(
      title: widget.title ?? 'Documentation',
      debugShowCheckedModeBanner: false,
      theme: dvDocsTheme(.light),
      darkTheme: dvDocsTheme(.dark),
      home: DVDocsUnavailable(failure: failure),
    );
  }
}

/// The site could not be drawn from a document.
///
/// Says what it was asked for and what answered. The second line is the whole
/// point: the commonest cause is a directory still serving the hand-written
/// pages this replaced, or an application mounted where the payload is not, and
/// both answer with something that is not a document rather than with nothing.
class DVDocsUnavailable extends StatelessWidget {
  const DVDocsUnavailable({super.key, required this.failure});

  /// What reading the document threw.
  final Object failure;

  @override
  Widget build(BuildContext context) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    return Material(
      child: Center(
        child: SingleChildScrollView(
          padding: const .all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: dvDocsMeasure / 2),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    'Documentation unavailable',
                    style: docs.heading(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The documentation document could not be read.',
                  style: docs.body,
                ),
                const SizedBox(height: 8),
                Text('$failure', style: docs.source),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One page of the site: its header, its navigation and the page itself.
///
/// Stateless, because the whole of its state is the address: a page the
/// document has is drawn, and a page it does not is the framework's own
/// not-found page under the same header, so a mistyped address still offers
/// the site's own pages rather than a dead end.
class DVDocsSite extends StatelessWidget {
  const DVDocsSite({
    super.key,
    required this.document,
    required this.path,
    this.fragment = '',
  });

  final DVDocsDocument document;

  /// The path the address named.
  final String path;

  /// The anchor after the `#`, if there was one.
  final String fragment;

  /// The page at [path], or null when the document has no such page.
  static DVDocsPage? pageAt(DVDocsDocument document, String path) {
    for (final DVDocsPage page in document.pages) {
      if (_plain(page.path) == _plain(path)) return page;
    }
    return null;
  }

  /// A path without its trailing slash, and never empty.
  ///
  /// `/models` and `/models/` are the same page, and neither is the
  /// document's problem, so neither of them is an error page.
  static String _plain(String path) {
    if (path.isEmpty) return '/';
    return path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
  }

  @override
  Widget build(BuildContext context) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    final DVDocsPage? page = pageAt(document, path);
    return Scaffold(
      backgroundColor: docs.theme.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            _DocsHeader(document: document, current: page),
            Expanded(
              child: page == null
                  ? DVNotFoundPage(route: _plain(path))
                  : SingleChildScrollView(
                      child: Align(
                        alignment: .topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: dvDocsMeasure,
                          ),
                          child: Padding(
                            padding: const .symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            child: _DVDocsBody(
                              // A page is a page: the body keeps its anchor
                              // keys per page, so a new page starts with a new
                              // set rather than reusing the last one's.
                              key: ValueKey<String>(page.id),
                              document: document,
                              page: page,
                              fragment: fragment,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The application's name, and the pages it has.
///
/// The stylesheet had a `<strong>` and a `<nav>`, and this is them: the name,
/// then the pages under it, with the one being read marked. Each is a link to
/// a page the document has; a page it does not is shown as its label rather
/// than as a link that goes nowhere.
class _DocsHeader extends StatelessWidget {
  const _DocsHeader({required this.document, required this.current});

  final DVDocsDocument document;

  /// The page on screen, or null when it is the not-found page.
  final DVDocsPage? current;

  @override
  Widget build(BuildContext context) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: docs.theme.rule)),
      ),
      child: Align(
        alignment: .topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: dvDocsMeasure),
          child: Padding(
            padding: const .symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Text(
                  document.application,
                  style: docs.body.copyWith(fontSize: 16, fontWeight: .w600),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 16,
                  runSpacing: 2,
                  children: <Widget>[
                    for (final (String id, String label)
                        in document.navigation)
                      _link(context, id, label),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _link(BuildContext context, String id, String label) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    final DVDocsPage? page = document.page(id);
    if (page == null) {
      return Text(
        label,
        style: docs.body.copyWith(color: docs.theme.muted),
      );
    }
    final bool here = page.id == current?.id;
    return DVNavLink(
      to: DVRouteTarget(page.path),
      // Nothing to preload and nowhere to preview: every page of this site is
      // already in memory, and a preview of it would be a second copy of the
      // page on screen.
      preload: DVLinkPreload.none,
      preview: DVLinkPreview.none,
      semanticLabel: label,
      padding: const .symmetric(vertical: 4),
      child: Text(
        label,
        style: docs.body.copyWith(
          fontWeight: here ? .w600 : .w400,
          color: here ? docs.theme.warn : docs.theme.ink,
        ),
      ),
    );
  }
}

/// A page's title, its blocks, and the anchor in the address.
class _DVDocsBody extends StatefulWidget {
  const _DVDocsBody({
    super.key,
    required this.document,
    required this.page,
    required this.fragment,
  });

  final DVDocsDocument document;
  final DVDocsPage page;
  final String fragment;

  @override
  State<_DVDocsBody> createState() => _DVDocsBodyState();
}

class _DVDocsBodyState extends State<_DVDocsBody> {
  late final DVDocsAnchors _anchors = DVDocsAnchors(widget.page);
  late final DVDocsLinkSpan _link = dvDocsLinkSpan(widget.document);

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(covariant _DVDocsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fragment != oldWidget.fragment) _reveal();
  }

  /// Puts the block the address names on the screen.
  ///
  /// After the frame the page is laid out in: a key is not a place until its
  /// widget is built, and arriving on a page and being put at a row is two
  /// frames of work the reader waits for either way.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _anchors.reveal(widget.fragment);
    });
  }

  @override
  Widget build(BuildContext context) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    final DVDocsPage page = widget.page;
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(page.title, style: docs.title),
        ),
        if (page.source != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(page.source!, style: docs.source),
        ],
        const SizedBox(height: 16),
        for (final DVDocsBlock block in page.blocks)
          DVDocsBlockView(block: block, anchors: _anchors, link: _link),
        const SizedBox(height: 32),
        Text('graph v${widget.document.graphVersion}', style: docs.source),
      ],
    );
  }
}

/// How a link in a block is drawn here.
///
/// A page of this document routes, with its anchor when it carries one. A page
/// it does not have is its own text: a link to nowhere is not a link, and a
/// site that answered "not found" where a reader followed a decision record's
/// reference has failed at the one job it has. An address that leaves the site
/// is opened through the app's own way out, so a kiosk policy and a host
/// application's handler both still see it.
DVDocsLinkSpan dvDocsLinkSpan(DVDocsDocument document) {
  return (BuildContext context, String text, DVDocsTarget target) {
    final DVDocsStyle docs = DVDocsStyle.of(context);
    final String? href = target.href;
    if (href != null) {
      if (href.startsWith('http://') || href.startsWith('https://')) {
        return WidgetSpan(
          child: DVNavLink.external(
            href,
            semanticLabel: text,
            padding: const .symmetric(vertical: 2),
            child: Text(text, style: docs.link),
          ),
        );
      }
      // A path on this site. The document mounts inside the application it
      // documents, so its own paths are the application's.
      return WidgetSpan(
        child: _route(DVRouteTarget(href), text, docs.link),
      );
    }
    final DVDocsPage? page = document.page(target.page ?? '');
    if (page == null) return null;
    final String? anchor = target.anchor;
    return WidgetSpan(
      child: _route(
        DVRouteTarget(
          anchor == null || anchor.isEmpty ? page.path : '${page.path}#$anchor',
        ),
        text,
        docs.link,
      ),
    );
  };
}

/// A link to a place on this site.
///
/// [style] rather than a lookup, because the link is a widget in a span tree
/// and has to be told what the run around it is drawn in; a link whose text
/// fell back to the default would be the one run in a paragraph the reader had
/// to guess at.
Widget _route(DVRouteTarget to, String text, TextStyle style) => DVNavLink(
  to: to,
  preload: DVLinkPreload.none,
  preview: DVLinkPreview.none,
  semanticLabel: text,
  padding: const .symmetric(vertical: 2),
  child: Text(text, style: style),
);
