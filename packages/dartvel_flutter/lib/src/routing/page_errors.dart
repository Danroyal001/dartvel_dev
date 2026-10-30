/// The pages an app shows when a page cannot be shown.
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

import '../../dartvel_flutter.dart' show DV, DVFrameworkStrings, DVNavLink, DVRouteTarget, DVTranslationKey;

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
    title: DV.I18n.t(DVFrameworkStrings.notFoundTitle),
    // A path is a person's own input echoed back, and it is inside a text
    // node, so the capture escapes it like any other text.
    body: <String>[
      DV.I18n.t(DVFrameworkStrings.notFoundAt, args: <String, String>{'route': route}),
      DV.I18n.t(DVFrameworkStrings.notFoundHint),
    ],
    children: <Widget>[
      _DVLinkButton(to: const DVRouteTarget('/'), label: DV.I18n.t(DVFrameworkStrings.goHome)),
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
      title: DV.I18n.t(DVFrameworkStrings.offlineTitle),
      body: <String>[
        DV.I18n.t(DVFrameworkStrings.offlineCached),
        if (from != null && from!.isNotEmpty)
          DV.I18n.t(DVFrameworkStrings.offlineCouldNotOpen, args: <String, String>{'route': from!}),
        DV.I18n.t(DVFrameworkStrings.offlineCheck),
      ],
      children: <Widget>[
        _DVLinkButton(to: DVRouteTarget(target), label: DV.I18n.t(DVFrameworkStrings.retry)),
      ],
    );
  }
}

/// The page for a status code a server answered a page request with.
///
/// Status pages are generated per code: a 500 is not a stack trace in front
/// of a customer, and the detail a developer needs goes to the log while the
/// visitor gets a sentence. So this takes the code and nothing else -- there
/// is no parameter through which an error, a message or a stack could reach
/// the reader.
///
/// Each code says what it means for the person reading it, because the
/// answers differ: a 429 asks them to wait, a 503 says the application is
/// down for now, a 403 says the page is not theirs to see, and a 500 says the
/// fault is the application's. A code with no sentence of its own reads as
/// a 500, which is the honest default for a failure the page cannot name.
class DVStatusPage extends StatelessWidget {
  const DVStatusPage({super.key, required this.code});

  /// The HTTP status the page request was answered with.
  final int code;

  @override
  Widget build(BuildContext context) {
    final (DVTranslationKey title, DVTranslationKey body) = switch (code) {
      403 => (DVFrameworkStrings.status403Title, DVFrameworkStrings.status403Body),
      429 => (DVFrameworkStrings.status429Title, DVFrameworkStrings.status429Body),
      503 => (DVFrameworkStrings.status503Title, DVFrameworkStrings.status503Body),
      _ => (DVFrameworkStrings.status500Title, DVFrameworkStrings.status500Body),
    };
    return _DVErrorPage(
      title: DV.I18n.t(title),
      body: <String>[DV.I18n.t(body)],
      children: <Widget>[
        _DVLinkButton(
          to: const DVRouteTarget('/'),
          label: DV.I18n.t(DVFrameworkStrings.goHome),
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
              // Level 1: the capture's <h1>, which the accessibility gate
              // requires of every captured route. A bare header is a heading
              // of no level, and a page of those names nothing.
              Semantics(
                header: true,
                headingLevel: 1,
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

/// A link drawn as the application's primary button.
///
/// A link, because where it goes is a page: a crawler reads it as
/// `<a href>`, a screen reader announces a link, a middle click opens a tab
/// and the keyboard reaches it -- all of which [DVNavLink] already is. Drawn
/// as a filled button in the application's theme, because the one thing a
/// person on an error page is looking for is the way out, and a line of plain
/// text did not look like anything that could be pressed. Hover, focus and
/// press are the theme's own filled-button states, with a visible outline on
/// keyboard focus, and it is never smaller than a finger.
class _DVLinkButton extends StatefulWidget {
  const _DVLinkButton({required this.to, required this.label});

  final DVRouteTarget to;
  final String label;

  @override
  State<_DVLinkButton> createState() => _DVLinkButtonState();
}

class _DVLinkButtonState extends State<_DVLinkButton> {
  final FocusNode _focus = FocusNode(debugLabel: 'DVLinkButton');
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // The application's filled-button theme over Material's filled button,
    // so an app that styled its buttons gets its own here too.
    final ButtonStyle style = (theme.filledButtonTheme.style ??
            const ButtonStyle())
        .merge(FilledButton.styleFrom(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      textStyle: theme.textTheme.labelLarge,
      minimumSize: const Size(64, 48),
      padding: const .symmetric(horizontal: 24, vertical: 12),
      shape: const StadiumBorder(),
    ));
    final bool focused = _focus.hasFocus;
    final Set<WidgetState> states = <WidgetState>{
      if (_hovered) WidgetState.hovered,
      if (focused) WidgetState.focused,
      if (_pressed) WidgetState.pressed,
    };
    final Color background =
        style.backgroundColor?.resolve(states) ?? scheme.primary;
    final Color? overlay = style.overlayColor?.resolve(states);
    final Color foreground =
        style.foregroundColor?.resolve(states) ?? scheme.onPrimary;
    final OutlinedBorder shape =
        style.shape?.resolve(states) ?? const StadiumBorder();
    return DVNavLink(
      to: widget.to,
      padding: .zero,
      focusNode: _focus,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: Listener(
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: style.minimumSize?.resolve(states)?.width ?? 64,
              minHeight: style.minimumSize?.resolve(states)?.height ?? 48,
            ),
            child: Material(
              color: overlay == null
                  ? background
                  : Color.alphaBlend(overlay, background),
              shape: focused
                  ? shape.copyWith(
                      side: BorderSide(color: scheme.onSurface, width: 2),
                    )
                  : shape,
              child: Padding(
                padding: style.padding?.resolve(states) ??
                    const .symmetric(horizontal: 24, vertical: 12),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: DefaultTextStyle.merge(
                    style: (style.textStyle?.resolve(states) ??
                            theme.textTheme.labelLarge ??
                            const TextStyle())
                        .copyWith(color: foreground),
                    child: Text(widget.label),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
