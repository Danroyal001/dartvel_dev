/// The two pages an app shows when a page cannot be shown.
///
/// One is a path with nothing at it, and the other is a path the device
/// cannot reach. Both used to be documents the build wrote by hand, which put
/// two pages in every application that no `@DVPage` declared, no theme
/// reached and nobody could edit — and the offline one, being served exactly
/// when the network is gone, could not have been a real page even in
/// principle.
///
/// Each one is a route the generator declares and the build prerenders like
/// any other, so both need what every captured route needs: a heading, which
/// is what becomes the `<h1>` the accessibility gate demands and what a
/// reader of the captured text has to go on, and a real link, which is what
/// a crawler follows and a switch or a remote reaches.
library dartvel_flutter.routing.page_errors;

import 'package:dartvel_core/dartvel.dart' show dvOfflineReturn;
import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart' show DVNavLink, DVRouteTarget;

/// A path with nothing at it.
///
/// [route] is what was asked for, and is shown: a person who mistyped a link
/// and a person whose crawler followed a stale one can both see which link was
/// wrong, and a report about a page somebody cannot name is a report nobody
/// can act on.
class DVNotFoundPage extends StatelessWidget {
  const DVNotFoundPage({super.key, required this.route});

  /// The path that was asked for.
  final String route;

  @override
  Widget build(BuildContext context) => _DVErrorPage(
    title: 'Page not found',
    // A path is a person's own input echoed back, and it is inside a text
    // node, so the capture escapes it like any other text.
    body: <String>[
      'Nothing is at $route.',
      'The link may be wrong, or the page may have moved.',
    ],
    children: <Widget>[
      DVNavLink(
        to: const DVRouteTarget('/'),
        child: Text('Go to the home page', style: _linkStyle(context)),
      ),
    ],
  );
}

/// The device cannot reach the network.
///
/// Shown by a service worker when a navigation fails, so it renders with
/// whatever the device already has — the app is already running, which is the
/// only reason anything can be shown at all.
///
/// [from] is the path the person was trying to open. It arrives in a query
/// string, which anybody can write, so it goes through the same rule the
/// second-factor challenge uses and becomes `/` when it could lead off this
/// site — or back here, which is a redirect that never lands.
class DVOfflinePage extends StatelessWidget {
  const DVOfflinePage({super.key, this.from});

  /// Where the person was going, when the failure named it.
  final String? from;

  @override
  Widget build(BuildContext context) {
    final String target = dvOfflineReturn(from);
    return _DVErrorPage(
      title: 'You are offline',
      body: <String>[
        'This page is on this device, so it works without a network.',
        if (from != null && from!.isNotEmpty)
          'Dartvel could not open $from.',
        'Check the connection, then try again.',
      ],
      children: <Widget>[
        DVNavLink(
          to: DVRouteTarget(target),
          child: Text('Try again', style: _linkStyle(context)),
        ),
      ],
    );
  }
}

/// The frame both pages share.
///
/// A router's error page has no Scaffold above it, so bare text there takes
/// Flutter's fallback error style: red, with yellow double underlines. The
/// Material is what supplies the app theme's text styles and canvas instead,
/// light or dark.
class _DVErrorPage extends StatelessWidget {
  const _DVErrorPage({
    required this.title,
    required this.body,
    required this.children,
  });

  final String title;
  final List<String> body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Material(
      child: Center(
        child: SingleChildScrollView(
          padding: const .all(24),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(title, style: text.headlineMedium),
              ),
              const SizedBox(height: 12),
              for (final String line in body) ...<Widget>[
                Text(line, style: text.bodyLarge),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle? _linkStyle(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  return theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.primary,
        decoration: .underline,
        decorationColor: theme.colorScheme.primary,
      );
}
