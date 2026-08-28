/// A link, rather than a tap handler someone remembered to wire.
///
/// The dartvel.dev header was hand-rolled twice and dead once, because a
/// `GestureDetector` on text is easy to write and easy to write wrongly:
/// `onTap: () => DV.Navigation.to(target)` compiles, runs, and navigates
/// nowhere. A link is a thing with behaviour.
///
/// Most of that behaviour does not exist in a Flutter app by default. The app
/// is a canvas, so there is no anchor for the browser or the OS to act on:
/// nothing shows the destination, nothing opens a new tab on a middle click,
/// nothing takes keyboard focus, and nothing previews where you are about to
/// go. Each is built here, and each works the same on every platform — a
/// desktop, a phone, a television and the web — rather than only where the
/// system happens to provide it.
library dartvel_flutter.routing.nav_link;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../dartvel_flutter.dart' show DV, DVRouteTarget;

/// When a link fetches the route it points at.
enum DVLinkPreload {
  /// Never. For a link into something expensive that most visitors skip.
  none,

  /// When the pointer arrives. A hover precedes the click by a few hundred
  /// milliseconds, which is most of a page load.
  hover,

  /// As soon as the link is built, for the destination most visitors take.
  immediate,
}

/// Whether a link shows what it points at.
enum DVLinkPreview {
  /// No preview.
  none,

  /// On a resting pointer, and on a long press where there is no pointer.
  /// The default, because a link that shows you where you are going is
  /// better than one that does not, on every platform rather than one.
  auto,
}

/// Called with the destination when the pointer enters a link, and null when
/// it leaves.
typedef DVLinkPreviewCallback = void Function(String? path);

/// How long a pointer rests before the preview appears.
///
/// Long enough that crossing a link on the way somewhere else does not flash
/// a card; short enough to feel like an answer rather than a wait.
const Duration dvLinkPreviewDelay = Duration(milliseconds: 550);

/// A navigable link to a route.
class DVNavLink extends StatefulWidget {
  const DVNavLink({
    super.key,
    required this.to,
    required this.child,
    this.preload = DVLinkPreload.hover,
    this.preview = DVLinkPreview.auto,
    this.onPreload,
    this.onPreview,
    this.openInNewTab,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    this.enabled = true,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  })  : externalUrl = null,
        assert(true);

  /// A link that leaves the site.
  ///
  /// Everything a route link is — a real anchor a crawler follows and a
  /// screen reader announces, keyboard focus, Enter — pointed at another
  /// address. Without it there was no way to write a link to GitHub or
  /// pub.dev, and the obvious workaround is styled text that does nothing:
  /// it looks exactly like a working link and is dead.
  ///
  /// It opens rather than routes. The router has no route for another origin,
  /// and the web interceptor already leaves other origins to the browser, so
  /// this and that agree by construction.
  ///
  /// It does not preload or preview. Both render the destination, and there
  /// is no destination widget for somebody else's site.
  const DVNavLink.external(
    String url, {
    super.key,
    required this.child,
    this.openInNewTab,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    this.enabled = true,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  })  : externalUrl = url,
        to = const DVRouteTarget('/'),
        preload = DVLinkPreload.none,
        preview = DVLinkPreview.none,
        onPreload = null,
        onPreview = null;

  /// Where this goes when it leaves the site, or null for a route link.
  final String? externalUrl;

  /// Where it goes.
  final DVRouteTarget to;

  /// What it looks like.
  final Widget child;

  /// When to fetch the destination.
  final DVLinkPreload preload;

  /// Whether to show the destination on a rest or a long press.
  final DVLinkPreview preview;

  /// How to fetch the destination. Defaults to the route's own loader.
  final Future<void> Function()? onPreload;

  /// Where to report the destination, for a status strip or similar.
  final DVLinkPreviewCallback? onPreview;

  /// How to open the destination beside this one, for a middle or modifier
  /// click. Defaults to the platform's own way of doing it.
  final void Function(String path)? openInNewTab;

  /// The hit area around [child]. Padding here rather than on the child means
  /// the space around the label is clickable, so a click that looks
  /// on-target does not miss.
  final EdgeInsets padding;

  /// Whether it navigates. A disabled link still renders.
  final bool enabled;

  /// What a screen reader reads. Defaults to whatever [child] announces.
  final String? semanticLabel;

  /// The node this link focuses. Supplied where a caller wants to move focus
  /// to it, or read it; otherwise the link owns one.
  final FocusNode? focusNode;

  /// Whether this link takes focus when it appears. For the first link on a
  /// page a keyboard user has just arrived at.
  final bool autofocus;

  @override
  State<DVNavLink> createState() => _DVNavLinkState();
}

class _DVNavLinkState extends State<DVNavLink> {
  /// Fetched once per link: a preload that refires on every pointer event
  /// turns a hover into a burst of requests.
  bool _preloaded = false;
  Timer? _previewTimer;
  OverlayEntry? _previewEntry;
  FocusNode? _ownedFocusNode;
  bool _focused = false;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode(debugLabel: 'DVNavLink'));

  @override
  void initState() {
    super.initState();
    if (widget.preload == DVLinkPreload.immediate) {
      // After the frame: a build must not start work that could rebuild it.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_preload()));
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _removePreview();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  Future<void> _preload() async {
    if (_preloaded || !widget.enabled) return;
    _preloaded = true;
    final loader = widget.onPreload ?? DVRoutePreloaders.forPath(widget.to.path);
    if (loader == null) return;
    try {
      await loader();
    } on Object catch (error, stack) {
      // Preloading is an optimisation, so a failure must not stop the tap
      // that follows. Reported rather than swallowed: a preload that silently
      // never works is a performance bug nobody can see.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'dartvel',
        context: ErrorDescription('preloading ${widget.to.path}'),
      ));
    }
  }

  void _enter(PointerEnterEvent _) {
    widget.onPreview?.call(widget.to.path);
    if (widget.preload == DVLinkPreload.hover) unawaited(_preload());
    _schedulePreview();
  }

  void _exit(PointerExitEvent _) {
    widget.onPreview?.call(null);
    _previewTimer?.cancel();
    _removePreview();
  }

  void _schedulePreview() {
    if (widget.preview == DVLinkPreview.none || !widget.enabled) return;
    _previewTimer?.cancel();
    _previewTimer = Timer(dvLinkPreviewDelay, _showPreview);
  }

  void _showPreview() {
    if (!mounted || _previewEntry != null) return;
    final builder = DVRoutePreviews.forPath(widget.to.path);
    // Nothing registered for this route. Quietly nothing, rather than an
    // empty card that looks like a failure.
    if (builder == null) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);

    _previewEntry = OverlayEntry(
      builder: (BuildContext overlayContext) => _DVLinkPreviewCard(
        anchor: Rect.fromLTWH(
          origin.dx,
          origin.dy,
          box.size.width,
          box.size.height,
        ),
        path: widget.to.path,
        child: Builder(builder: builder),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_previewEntry!);
  }

  void _removePreview() {
    _previewEntry?.remove();
    _previewEntry = null;
  }

  /// Whether this click means "beside this page" rather than "instead of it".
  bool get _wantsNewTab {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  void _openBeside() {
    _previewTimer?.cancel();
    _removePreview();
    final String destination = widget.externalUrl ?? widget.to.path;
    final void Function(String)? override = widget.openInNewTab;
    if (override != null) {
      override(destination);
    } else {
      DVLinkOpener.open(destination, newTab: true);
    }
  }

  void _activate() {
    if (!widget.enabled) return;
    _previewTimer?.cancel();
    _removePreview();
    final String? external = widget.externalUrl;
    if (external != null) {
      // Opened, never routed. The router has no route for another origin.
      DVLinkOpener.open(external);
      return;
    }
    if (_wantsNewTab) {
      _openBeside();
      return;
    }
    DV.Navigation.navigate(widget.to);
  }

  void _onPointerDown(PointerDownEvent event) {
    // A middle click is the reflex that costs nothing on a real site and does
    // nothing on a Flutter one. It is handled on the down event because a
    // middle button never produces a tap.
    if (widget.enabled && event.buttons == kMiddleMouseButton) {
      _openBeside();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // A screen reader should hear a link and its destination, not a piece
      // of tappable text.
      link: true,
      linkUrl: Uri.tryParse(widget.externalUrl ?? widget.to.path),
      label: widget.semanticLabel,
      // An explicit label replaces the child's text rather than being read
      // before it. Without this a screen reader announces both -- "Read more
      // about pricing, Read more" -- which is worse than the bare label the
      // caller was trying to improve on.
      excludeSemantics: widget.semanticLabel != null,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: _enter,
        onExit: _exit,
        child: Listener(
          onPointerDown: _onPointerDown,
          // FocusableActionDetector rather than InkWell. InkWell gives focus,
          // Enter/Space and a focus ring, and also requires a Material
          // ancestor — which a link, being a primitive, cannot demand of the
          // tree it is dropped into. It threw "No Material widget found" on
          // every page built without a Scaffold; the widget suite missed it
          // by wrapping each subject in one.
          //
          // FocusableActionDetector is the same behaviour from the widgets
          // layer: focus, hover, and an Actions map that Enter and Space
          // already dispatch ActivateIntent into.
          child: FocusableActionDetector(
            enabled: widget.enabled,
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            mouseCursor: widget.enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onShowFocusHighlight: (bool value) {
              if (value != _focused && mounted) {
                setState(() => _focused = value);
              }
            },
            actions: <Type, Action<Intent>>{
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (ActivateIntent intent) {
                  _activate();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? _activate : null,
              onLongPress: widget.enabled ? _showPreview : null,
              child: DecoratedBox(
                // Focus nobody can see is focus nobody can follow. Drawn here
                // rather than taken from InkWell's focusColor, and from the
                // theme's own colour so it reads in light and dark.
                decoration: BoxDecoration(
                  color: _focused ? Theme.of(context).focusColor : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(padding: widget.padding, child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating card showing where a link goes.
class _DVLinkPreviewCard extends StatelessWidget {
  const _DVLinkPreviewCard({
    required this.anchor,
    required this.path,
    required this.child,
  });

  final Rect anchor;
  final String path;
  final Widget child;

  static const Size _size = Size(340, 240);

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // Below the link where there is room, above it where there is not, and
    // never off the side.
    final below = anchor.bottom + 10;
    final top = below + _size.height > screen.height
        ? (anchor.top - _size.height - 10).clamp(8.0, screen.height)
        : below;
    final left =
        anchor.left.clamp(8.0, (screen.width - _size.width - 8).clamp(8.0, screen.width));

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        // It is a picture of a destination, not the destination. A stray tap
        // inside must not activate whatever it happens to be showing.
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox.fromSize(
            size: _size,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 1200,
                      height: 850,
                      child: MediaQuery(
                        // The destination believes it has a full window, so
                        // it lays out the way it really would rather than
                        // collapsing into a card-sized shape.
                        data: MediaQuery.of(context).copyWith(
                          size: const Size(1200, 850),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opening a destination beside the current one.
///
/// On the web this is a new tab. Elsewhere there is nothing to open beside, so
/// the default does nothing rather than pretending — an app supplies its own
/// behaviour through [DVNavLink.openInNewTab] where it has one.
class DVLinkOpener {
  const DVLinkOpener._();

  static void Function(String path, {bool newTab})? _opener;

  /// Install the platform's way of doing it. Called by the generated router
  /// on the web.
  static void install(void Function(String path, {bool newTab}) opener) =>
      _opener = opener;

  /// Open [path], in this tab unless [newTab].
  ///
  /// The two are different intentions and were one function: following a
  /// footer link should replace the page, and a middle click should not.
  static void open(String path, {bool newTab = false}) =>
      _opener?.call(path, newTab: newTab);

  @visibleForTesting
  static void reset() => _opener = null;
}

/// Route loaders, so a link can fetch what it points at.
///
/// Dartvel pages are deferred: each carries a `loadLibrary()` that fetches its
/// bundle on first navigation. Registering those here lets a link do it early,
/// which is the whole trick — the same work, moved to the moment the pointer
/// arrives rather than the moment the click lands.
class DVRoutePreloaders {
  const DVRoutePreloaders._();

  static final Map<String, Future<void> Function()> _loaders =
      <String, Future<void> Function()>{};

  /// Register the loader for a path. Called by the generated router.
  static void register(String path, Future<void> Function() loader) =>
      _loaders[path] = loader;

  /// The loader for a path, or null when nothing registered one.
  static Future<void> Function()? forPath(String path) => _loaders[path];

  /// Forget everything, for tests and for a router being replaced.
  static void clear() => _loaders.clear();

  @visibleForTesting
  static int get count => _loaders.length;
}

/// Route builders, so a link can show what it points at.
class DVRoutePreviews {
  const DVRoutePreviews._();

  static final Map<String, WidgetBuilder> _builders = <String, WidgetBuilder>{};

  /// Register the builder for a path. Called by the generated router.
  static void register(String path, WidgetBuilder builder) =>
      _builders[path] = builder;

  /// The builder for a path, or null when nothing registered one.
  static WidgetBuilder? forPath(String path) => _builders[path];

  /// Forget everything, for tests and for a router being replaced.
  static void clear() => _builders.clear();

  @visibleForTesting
  static int get count => _builders.length;
}
