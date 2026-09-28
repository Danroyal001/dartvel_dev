/// Ctrl+K (Cmd+K on a Mac): a command palette over Studio.
///
/// Every section, every page, every element on the page being edited and
/// what can be done to it, found by typing a few letters of it -- the way
/// Framer, Webflow, Linear and VS Code all answer "how do I get to that"
/// without a menu. Up and Down move, Enter runs, Esc closes.
///
/// Commands are not a list somebody maintains. Each part of Studio provides
/// its own through [DVStudioCommandScope.provide] while it is on screen, so
/// the palette offers what can be done where the person is, and a section
/// that is gone takes its commands with it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Something the palette can do.
class DVStudioCommand {
  const DVStudioCommand({
    required this.id,
    required this.title,
    required this.run,
    this.group,
    this.keywords = const <String>[],
    this.shortcut,
  });

  final String id;
  final String title;

  /// A heading the palette groups it under: Go to, Page, Element.
  final String? group;

  /// Other words it answers to.
  final List<String> keywords;

  /// The key that does the same thing, shown beside it.
  final String? shortcut;

  final VoidCallback run;
}

/// [commands] matching [query], best first.
///
/// A match is the query's letters in order within the title or a keyword.
/// A match at the start of a word, and letters that run together, score
/// higher, so `gtp` finds "Go to Pages" before "Go to Flags" does not match
/// at all. An empty query keeps the order given.
List<DVStudioCommand> dvRankCommands(String query, List<DVStudioCommand> commands) {
  final String q = query.trim().toLowerCase();
  if (q.isEmpty) return List<DVStudioCommand>.of(commands);
  final List<(DVStudioCommand, int)> scored = <(DVStudioCommand, int)>[];
  for (int index = 0; index < commands.length; index++) {
    final DVStudioCommand c = commands[index];
    int? best;
    for (final String text in <String>[c.title, ...c.keywords]) {
      final int? s = _score(q, text.toLowerCase());
      if (s != null && (best == null || s > best)) best = s;
    }
    if (best != null) scored.add((c, best * 1000 - index));
  }
  scored.sort(((DVStudioCommand, int) a, (DVStudioCommand, int) b) => b.$2.compareTo(a.$2));
  return <DVStudioCommand>[for (final (DVStudioCommand c, int _) in scored) c];
}

int? _score(String q, String text) {
  int score = 0;
  int at = 0;
  int? previous;
  for (int i = 0; i < q.length; i++) {
    final int found = text.indexOf(q[i], at);
    if (found < 0) return null;
    if (found == 0 || text[found - 1] == ' ' || text[found - 1] == '/') score += 10;
    if (previous != null && found == previous + 1) score += 5;
    score -= found - at;
    previous = found;
    at = found + 1;
  }
  if (text.startsWith(q)) score += 50;
  return score;
}

/// Where Studio's commands are gathered, and the Ctrl+K that opens them.
class DVStudioCommandScope extends StatefulWidget {
  const DVStudioCommandScope({super.key, required this.child});

  final Widget child;

  /// Adds [commands] under [owner], replacing what [owner] provided before.
  /// Called from build, so a part of Studio provides what applies to it now.
  static void provide(BuildContext context, Object owner,
      List<DVStudioCommand> Function() commands) {
    context
        .findAncestorStateOfType<_DVStudioCommandScopeState>()
        ?._providers[owner] = commands;
  }

  /// Takes back what [owner] provided: its part of Studio has gone.
  static void withdraw(BuildContext context, Object owner) {
    context
        .findAncestorStateOfType<_DVStudioCommandScopeState>()
        ?._providers
        .remove(owner);
  }

  /// Opens the palette over [context].
  static Future<void> open(BuildContext context) async {
    final _DVStudioCommandScopeState? scope =
        context.findAncestorStateOfType<_DVStudioCommandScopeState>();
    if (scope == null) return;
    await scope._open();
  }

  @override
  State<DVStudioCommandScope> createState() => _DVStudioCommandScopeState();
}

class _DVStudioCommandScopeState extends State<DVStudioCommandScope> {
  final Map<Object, List<DVStudioCommand> Function()> _providers =
      <Object, List<DVStudioCommand> Function()>{};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    // At the keyboard rather than in the focus chain: a text field that has
    // focus -- the formula bar, a property -- takes Ctrl+K for itself
    // otherwise, and the palette is wanted from exactly there.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final bool command = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!command) return false;
    // Only for the Studio on top: not from under a dialog, not from a page
    // pushed over it.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyK) {
      unawaited(_open());
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.slash) {
      unawaited(dvShowStudioShortcuts(context));
      return true;
    }
    return false;
  }

  List<DVStudioCommand> get _commands => <DVStudioCommand>[
        for (final List<DVStudioCommand> Function() p in _providers.values) ...p(),
      ];

  Future<void> _open() async {
    if (_showing) return;
    _showing = true;
    try {
      final DVStudioCommand? chosen = await showDialog<DVStudioCommand>(
        context: context,
        barrierColor: const Color(0x33000000),
        builder: (BuildContext context) =>
            DVStudioCommandPalette(commands: _commands),
      );
      chosen?.run();
    } finally {
      _showing = false;
    }
  }

  // Focusable itself, and focused when Studio opens, so a key reaches
  // Studio before anything inside has been clicked.
  @override
  Widget build(BuildContext context) => Focus(
        autofocus: true,
        skipTraversal: true,
        debugLabel: 'DVStudioCommandScope',
        child: widget.child,
      );
}

/// The palette itself: a search line and what it finds.
class DVStudioCommandPalette extends StatefulWidget {
  const DVStudioCommandPalette({super.key, required this.commands});

  final List<DVStudioCommand> commands;

  static const Key searchKey = ValueKey<String>('dv-studio-command-search');

  @override
  State<DVStudioCommandPalette> createState() => _DVStudioCommandPaletteState();
}

class _DVStudioCommandPaletteState extends State<DVStudioCommandPalette> {
  final TextEditingController _query = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  int _selected = 0;

  List<DVStudioCommand> get _found => dvRankCommands(_query.text, widget.commands);

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final int count = _found.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && count > 0) {
      setState(() => _selected = (_selected + 1) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && count > 0) {
      setState(() => _selected = (_selected - 1 + count) % count);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _run();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _run([DVStudioCommand? command]) {
    final List<DVStudioCommand> found = _found;
    final DVStudioCommand? chosen =
        command ?? (found.isEmpty ? null : found[_selected.clamp(0, found.length - 1)]);
    if (chosen != null) Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final List<DVStudioCommand> found = _found;
    final ThemeData theme = Theme.of(context);
    return Align(
      alignment: const Alignment(0, -0.6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Material(
          elevation: 12,
          borderRadius: .circular(12),
          clipBehavior: .antiAlias,
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              Padding(
                padding: const .all(12),
                child: TextField(
                  key: DVStudioCommandPalette.searchKey,
                  controller: _query,
                  focusNode: _focus,
                  autofocus: true,
                  textInputAction: .go,
                  onChanged: (_) => setState(() => _selected = 0),
                  onSubmitted: (_) => _run(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Type a command, a page or an element',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Flexible(
                child: found.isEmpty
                    ? const Padding(
                        padding: .all(16),
                        child: Text('Nothing matches.'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: found.length,
                        itemBuilder: (BuildContext context, int i) {
                          final DVStudioCommand c = found[i];
                          return ListTile(
                            dense: true,
                            selected: i == _selected,
                            selectedTileColor:
                                theme.colorScheme.primary.withValues(alpha: 0.08),
                            title: Text(c.title),
                            subtitle: c.group == null ? null : Text(c.group!),
                            trailing: c.shortcut == null
                                ? null
                                : Text(c.shortcut!, style: theme.textTheme.labelSmall),
                            onTap: () => _run(c),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Studio's keyboard shortcuts, in one place: Ctrl+/ (Cmd+/) or the
/// palette's Keyboard shortcuts.
const List<(String, String)> dvStudioShortcuts = <(String, String)>[
  ('Ctrl+K', 'Open the command palette'),
  ('Ctrl+Z', 'Undo'),
  ('Ctrl+Shift+Z', 'Redo'),
  ('Ctrl+D', 'Duplicate the selected element'),
  ('Delete', 'Delete the selected element'),
  ('Esc', 'Deselect; in the formula bar, put back what was there'),
  ('Enter', 'Apply the formula'),
  ('Ctrl+Enter', 'Apply the formula when the bar has several lines'),
  ('Tab', 'Take the first completion in the formula bar'),
  ('Ctrl+/', 'Show these shortcuts'),
];

/// Shows [dvStudioShortcuts]. Cmd stands for Ctrl on a Mac.
Future<void> dvShowStudioShortcuts(BuildContext context) => showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              for (final (String keys, String what) in dvStudioShortcuts)
                ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 110,
                    child: Text(keys,
                        style: const TextStyle(fontFamily: 'monospace')),
                  ),
                  title: Text(what),
                ),
              const Padding(
                padding: .only(top: 8),
                child: Text('On a Mac, Cmd in place of Ctrl.'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
