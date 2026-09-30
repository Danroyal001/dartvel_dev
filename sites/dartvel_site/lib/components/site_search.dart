// The site search: a button in the header, Ctrl+K or Cmd+K anywhere, and a
// panel that asks the server's /api/search as the reader types.
//
// The panel is the whole screen on a phone, where a floating box would leave
// the keyboard covering half of it, and a column near the top of the window
// everywhere else. Up and down move through the results, Enter opens one and
// Escape closes the panel.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// One page the search found.
class const SiteSearchItem({
  required final String title,
  required final String heading,
  required final String snippet,
  required final String href,
});

/// What a search came back with.
class const SiteSearchAnswer({
  final List<SiteSearchItem> items = const <SiteSearchItem>[],

  /// The server said this caller has searched too often (429).
  final bool limited = false,

  /// The server did not answer, or answered with something else.
  final bool failed = false,
});

/// How the panel asks for results. The real one calls the server; a test
/// hands in its own.
typedef SiteSearchFetch = Future<SiteSearchAnswer> Function(String query);

/// Asks the server's search function.
Future<SiteSearchAnswer> fetchSiteSearch(String query) async {
  try {
    final DVHttpResponse response =
        await getSearch(query: <String, Object?>{'q': query});
    if (response.statusCode == 429) return const SiteSearchAnswer(limited: true);
    final Object? data = response.statusCode == 200 ? response.data : null;
    if (data is! List) return const SiteSearchAnswer(failed: true);
    return SiteSearchAnswer(items: <SiteSearchItem>[
      for (final Object? entry in data)
        if (entry is Map)
          SiteSearchItem(
            title: '${entry['title'] ?? ''}',
            heading: '${entry['heading'] ?? ''}',
            snippet: '${entry['snippet'] ?? ''}',
            href: '${entry['href'] ?? entry['path'] ?? '/'}',
          ),
    ]);
  } on Object {
    return const SiteSearchAnswer(failed: true);
  }
}

/// Whether the reader's platform calls the modifier Cmd rather than Ctrl.
bool siteSearchUsesCommand(BuildContext context) {
  final TargetPlatform platform = Theme.of(context).platform;
  return platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
}

/// Opens the search panel over the page [context] is in.
Future<void> openSiteSearch(
  BuildContext context, {
  SiteSearchFetch fetch = fetchSiteSearch,
}) {
  final GoRouter? router = GoRouter.maybeOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close search',
    barrierColor: const Color(0x99000000),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (BuildContext dialog, _, _) => SiteSearchPanel(
      fetch: fetch,
      onOpen: (String href) {
        Navigator.of(dialog).pop();
        router?.go(href);
      },
    ),
  );
}

/// Ctrl+K, or Cmd+K on a Mac, opens the search from anywhere on the site.
///
/// Listened for on the keyboard itself rather than through the focus tree,
/// so it works whatever has focus, including nothing at all, which is where
/// a page is before the reader has clicked anything.
class const SiteSearchShortcut({
  super.key,
  required final Widget child,
  final SiteSearchFetch fetch = fetchSiteSearch,
}) extends StatefulWidget {
  @override
  State<SiteSearchShortcut> createState() => _SiteSearchShortcutState();
}

class _SiteSearchShortcutState extends State<SiteSearchShortcut> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyK) {
      return false;
    }
    final HardwareKeyboard keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return false;
    if (_open || !mounted) return true;
    _open = true;
    openSiteSearch(context, fetch: widget.fetch)
        .whenComplete(() => _open = false);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The header's way into the search: a field-shaped button with the
/// shortcut on it, or just the magnifier on a phone.
@DVFunctionalWidget()
Widget _siteSearchButton(BuildContext context) {
  final Palette palette = Palette.of(context);
  // The magnifier alone where the header is short of room.
  final bool compact = context.screen.isMobile || context.screen.isTablet;
  final String shortcut = siteSearchUsesCommand(context) ? 'Cmd K' : 'Ctrl K';
  return Semantics(
    button: true,
    label: 'Search the site',
    hint: compact ? null : 'Shortcut $shortcut',
    excludeSemantics: true,
    child: InkWell(
      onTap: () => openSiteSearch(context),
      borderRadius: BorderRadius.circular(10),
      child: DVBox(
        DVBox.row(<Widget>[
          Icon(Icons.search, size: 18, color: palette.muted),
          if (!compact)
            const DVText('Search').modifier(const DVModifier()
                .fontSize(14)
                .fontWeight(.w500)
                .color(palette.muted)),
          if (!compact)
            DVBox(
              DVText(shortcut).modifier(const DVModifier()
                  .fontSize(12)
                  .fontWeight(.w600)
                  .color(palette.faint)),
              const DVModifier()
                  .paddingSymmetric(horizontal: 6, vertical: 2)
                  .border(Border.all(color: palette.rule))
                  .rounded(6),
            ),
        ], spacing: 8),
        const DVModifier()
            .paddingSymmetric(horizontal: compact ? 8 : 12, vertical: 8)
            .border(Border.all(color: compact ? const Color(0x00000000) : palette.rule))
            .rounded(10),
      ),
    ),
  );
}

/// The search itself: a field and what it found.
class const SiteSearchPanel({
  super.key,
  required final SiteSearchFetch fetch,
  required final void Function(String href) onOpen,
  final Duration debounce = const Duration(milliseconds: 180),
}) extends StatefulWidget {
  @override
  State<SiteSearchPanel> createState() => _SiteSearchPanelState();
}

class _SiteSearchPanelState extends State<SiteSearchPanel> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _field = FocusNode();
  Timer? _wait;

  /// Which request the results on screen answer. A slow answer to "cac"
  /// arriving after the answer to "cache" is dropped rather than shown.
  int _asked = 0;
  String _shown = '';
  SiteSearchAnswer _answer = const SiteSearchAnswer();
  bool _busy = false;
  int _selected = 0;

  @override
  void dispose() {
    _wait?.cancel();
    _query.dispose();
    _field.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _wait?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _asked++;
        _shown = '';
        _answer = const SiteSearchAnswer();
        _busy = false;
      });
      return;
    }
    _wait = Timer(widget.debounce, () => _ask(text.trim()));
  }

  Future<void> _ask(String text) async {
    final int ticket = ++_asked;
    setState(() => _busy = true);
    final SiteSearchAnswer answer = await widget.fetch(text);
    if (!mounted || ticket != _asked) return;
    setState(() {
      _busy = false;
      _shown = text;
      _answer = answer;
      _selected = 0;
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final int count = _answer.items.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && count > 0) {
      setState(() => _selected = (_selected + 1) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && count > 0) {
      setState(() => _selected = (_selected - 1 + count) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && count > 0) {
      widget.onOpen(_answer.items[_selected].href);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final Palette palette = Palette.of(context);
    final bool phone = context.screen.isMobile;

    final Widget field = Focus(
      onKeyEvent: _key,
      child: TextField(
        controller: _query,
        focusNode: _field,
        autofocus: true,
        onChanged: _changed,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          if (_answer.items.isNotEmpty) {
            widget.onOpen(_answer.items[_selected].href);
          }
        },
        style: TextStyle(fontSize: 17, color: palette.ink),
        cursorColor: palette.accent,
        decoration: InputDecoration(
          hintText: 'Search the docs and guides',
          hintStyle: TextStyle(fontSize: 17, color: palette.faint),
          prefixIcon: Icon(Icons.search, color: palette.muted),
          border: InputBorder.none,
          contentPadding: const .symmetric(vertical: 16),
        ),
      ),
    );

    final Widget close = Semantics(
      button: true,
      label: 'Close search',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(10),
        child: DVBox(
          DVText(phone ? 'Close' : 'Esc').modifier(const DVModifier()
              .fontSize(phone ? 15 : 12)
              .fontWeight(.w600)
              .color(phone ? palette.accent : palette.faint)),
          const DVModifier()
              .paddingSymmetric(horizontal: 8, vertical: 6)
              .border(Border.all(
                  color: phone ? const Color(0x00000000) : palette.rule))
              .rounded(6),
        ),
      ),
    );

    final Widget panel = Material(
      color: palette.page,
      borderRadius: phone ? null : BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: DVBox.list(<Widget>[
        DVBox(
          DVBox.row(<Widget>[Expanded(child: field), close], spacing: 8),
          const DVModifier()
              .paddingSymmetric(horizontal: 16)
              .border(Border(bottom: BorderSide(color: palette.rule))),
        ),
        Flexible(child: _results(context, palette)),
      ], spacing: 0),
    );

    if (phone) return SafeArea(child: panel);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const .fromLTRB(16, 72, 16, 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          child: panel,
        ),
      ),
    );
  }

  Widget _results(BuildContext context, Palette palette) {
    Widget note(String text) => DVBox(
          DVText(text).modifier(const DVModifier()
              .fontSize(15)
              .lineHeight(1.5)
              .color(palette.muted)),
          const DVModifier().padding(20),
        );

    if (_answer.limited) {
      return note('Too many searches from your connection. Wait a minute '
          'and try again.');
    }
    if (_answer.failed) {
      return note('Search is not answering right now. The docs index is at '
          '/docs.');
    }
    if (_shown.isEmpty) {
      return note(_busy
          ? 'Searching...'
          : 'Type a question or a word: "run on my phone", "rate limit", '
              '"DV.Cache".');
    }
    if (_answer.items.isEmpty) {
      return note('Nothing on the site matches "$_shown".');
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const .symmetric(vertical: 8),
      itemCount: _answer.items.length,
      itemBuilder: (BuildContext context, int i) {
        final SiteSearchItem item = _answer.items[i];
        final bool selected = i == _selected;
        return Semantics(
          link: true,
          selected: selected,
          label: item.heading.isEmpty
              ? item.title
              : '${item.title}, ${item.heading}',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => widget.onOpen(item.href),
            onHover: (bool over) {
              if (over) setState(() => _selected = i);
            },
            child: DVBox(
              DVBox.list(<Widget>[
                DVText(item.title).modifier(const DVModifier()
                    .fontSize(15)
                    .fontWeight(.w600)
                    .color(selected ? palette.accent : palette.ink)
                    .maxLines(1)),
                if (item.heading.isNotEmpty)
                  DVText(item.heading).modifier(const DVModifier()
                      .fontSize(13)
                      .fontWeight(.w600)
                      .color(palette.muted)
                      .maxLines(1)),
                if (item.snippet.isNotEmpty)
                  DVText(item.snippet).modifier(const DVModifier()
                      .fontSize(14)
                      .lineHeight(1.45)
                      .color(palette.muted)
                      .maxLines(2)),
              ], spacing: 3, crossAlign: .start),
              const DVModifier()
                  .paddingSymmetric(horizontal: 20, vertical: 10)
                  .backgroundColor(
                      selected ? palette.surface : const Color(0x00000000)),
            ),
          ),
        );
      },
    );
  }
}
