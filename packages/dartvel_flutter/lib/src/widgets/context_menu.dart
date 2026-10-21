/// One context menu for a piece of the page, opened the way each platform
/// opens one.
///
/// A right-click with a mouse or a trackpad's secondary click (desktop, the
/// web, a tablet or phone with a pointer, a Chromebook), a long-press on a
/// touch screen (Android, iOS, iPadOS), the menu key or Shift+F10 on a
/// hardware keyboard (any of them, including a keyboard phone), and, for a
/// screen reader, each item as one of the element's actions: TalkBack's
/// actions menu, VoiceOver's actions rotor. One declaration, the same items
/// on every target, so an action reached by right-click on the desktop is not
/// missing on a phone.
///
/// It keeps the rules every other Dartvel menu keeps (the page's selection
/// menu, a link's menu):
///
/// * selected text inside it is the page's: a right-click or a long-press on
///   a selection gets Copy and Select all, not the application's items;
/// * on the web it ends with More, which hands the next right-click to the
///   browser's own menu, and Shift+right-click goes to the browser directly;
/// * every item shows its label as a tooltip and is read by that name.
library;

import 'package:flutter/gestures.dart'
    show LongPressGestureRecognizer, TapGestureRecognizer, kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectionStatus;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../../dartvel_flutter.dart' show DVMenuItem;
import 'browser_menu.dart' show DVBrowserMenu;

/// A context menu of [items] for [child]; [onSelected] gets the chosen
/// item's id.
class const DVContextMenu({
  super.key,
  required final List<DVMenuItem> items,
  required final ValueChanged<String> onSelected,
  required final Widget child,
}) extends StatefulWidget {
  @override
  State<DVContextMenu> createState() => _DVContextMenuState();
}

class _DVContextMenuState extends State<DVContextMenu> {
  final MenuController _controller = MenuController();
  final SelectionListenerNotifier _selection = SelectionListenerNotifier();

  @override
  void initState() {
    super.initState();
    // Off with the browser's menu, as a page does, so a right-click here is
    // not answered twice on a page with no shell above it.
    DVBrowserMenu.install();
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  /// Whether text inside is selected: then a right-click is about that text.
  bool get _textSelected {
    if (!_selection.registered) return false;
    return _selection.selection.status == SelectionStatus.uncollapsed;
  }

  void _openAt(Offset local) => _controller.open(position: local);

  void _openFromPointer(Offset local) {
    // Shift+right-click, or a right-click after More: the browser's turn.
    if (DVBrowserMenu.nextClickIsNative) return;
    if (_textSelected) return;
    _openAt(local);
  }

  void _openFromKeyboard() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    _openAt(box == null ? .zero : box.size.center(.zero));
  }

  void _choose(String id) {
    _controller.close();
    widget.onSelected(id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return .ignored;
    final bool menuKey = event.logicalKey == LogicalKeyboardKey.contextMenu;
    final bool shiftF10 = event.logicalKey == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed;
    if (!menuKey && !shiftF10) return .ignored;
    _openFromKeyboard();
    return .handled;
  }

  /// [label] as the item's tooltip and its name, per the hover rule.
  Widget _named(String label, Widget child) =>
      Tooltip(message: label, excludeFromSemantics: true, child: child);

  List<Widget> _entries(List<DVMenuItem> items, TargetPlatform platform) =>
      <Widget>[
        for (final DVMenuItem item in items)
          if (item.children.isNotEmpty)
            _named(
              item.label,
              SubmenuButton(
                menuChildren: _entries(item.children, platform),
                child: Text(item.label),
              ),
            )
          else
            _named(
              item.label,
              MenuItemButton(
                onPressed: item.enabled ? () => _choose(item.id) : null,
                trailingIcon: item.shortcut == null
                    ? null
                    : ExcludeSemantics(
                        child: Text(dvShortcutLabel(item.shortcut!, platform)),
                      ),
                child: Text(item.label),
              ),
            ),
      ];

  /// More, on the web: the browser's own menu, as in every Dartvel menu.
  Widget _more() => _named(
        'More',
        MenuItemButton(
          onPressed: () {
            final RenderBox? box = context.findRenderObject() as RenderBox?;
            _controller.close();
            DVBrowserMenu.openNextNative();
            if (box != null && box.attached) {
              DVBrowserMenu.showHint(context, box.localToGlobal(.zero));
            }
          },
          child: const Text('More'),
        ),
      );

  /// Every enabled leaf, for a screen reader: it has no pointer to open the
  /// menu with, so the items are the element's own actions.
  Map<CustomSemanticsAction, VoidCallback> _actions(List<DVMenuItem> items) =>
      <CustomSemanticsAction, VoidCallback>{
        for (final DVMenuItem item in items)
          if (item.children.isNotEmpty)
            ..._actions(item.children)
          else if (item.enabled)
            CustomSemanticsAction(label: item.label): () =>
                widget.onSelected(item.id),
      };

  @override
  Widget build(BuildContext context) {
    final TargetPlatform platform = Theme.of(context).platform;
    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      menuChildren: <Widget>[
        ..._entries(widget.items, platform),
        if (DVBrowserMenu.isWeb) _more(),
      ],
      child: Focus(
        onKeyEvent: _onKey,
        child: Semantics(
          customSemanticsActions: _actions(widget.items),
          child: RawGestureDetector(
            behavior: .opaque,
            gestures: <Type, GestureRecognizerFactory>{
              _DVMenuSecondaryTap:
                  GestureRecognizerFactoryWithHandlers<_DVMenuSecondaryTap>(
                () => _DVMenuSecondaryTap(
                    debugOwner: this, yieldsTo: () => _textSelected),
                (_DVMenuSecondaryTap recognizer) => recognizer
                  ..onSecondaryTapUp = (TapUpDetails details) =>
                      _openFromPointer(details.localPosition),
              ),
              _DVMenuLongPress:
                  GestureRecognizerFactoryWithHandlers<_DVMenuLongPress>(
                () => _DVMenuLongPress(
                    debugOwner: this, yieldsTo: () => _textSelected),
                (_DVMenuLongPress recognizer) => recognizer
                  ..onLongPressStart = (LongPressStartDetails details) =>
                      _openFromPointer(details.localPosition),
              ),
            },
            child: SelectionListener(
              selectionNotifier: _selection,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The menu's long-press. A control inside it has a tooltip that also
/// answers a long-press, and of two recognizers with the same deadline the
/// deeper one fires first, so the menu would never open on a tappable row.
/// This one's deadline is a little shorter: a long-press on something with a
/// menu opens the menu, which names the row's actions, and the tooltip still
/// shows on hover and on keyboard focus.
class _DVMenuLongPress extends LongPressGestureRecognizer {
  _DVMenuLongPress({super.debugOwner, required this.yieldsTo})
      : super(duration: kLongPressTimeout - const Duration(milliseconds: 50));

  /// True while selected text inside owns the press: the menu stays out of
  /// the gesture arena so the selection's own menu (Copy, Select all) opens.
  final bool Function() yieldsTo;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      !yieldsTo() && super.isPointerAllowed(event);
}

/// The menu's right-click. Like [_DVMenuLongPress] it steps aside while text
/// inside is selected, so the right-click reaches the selection's menu.
class _DVMenuSecondaryTap extends TapGestureRecognizer {
  _DVMenuSecondaryTap({super.debugOwner, required this.yieldsTo});

  final bool Function() yieldsTo;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      !yieldsTo() && super.isPointerAllowed(event);
}

/// [keys] (`mod+shift+r`) as the platform writes a shortcut: `⇧⌘R` on Apple
/// platforms, `Ctrl+Shift+R` elsewhere. `mod` is Command on Apple platforms
/// and Control everywhere else, as in DVShortcutScope.
String dvShortcutLabel(String keys, TargetPlatform platform) {
  final bool apple = platform == .macOS || platform == .iOS;
  final List<String> parts =
      keys.toLowerCase().split('+').map((String part) => part.trim()).toList();
  final String key = parts.removeLast();
  final Set<String> modifiers = <String>{
    for (final String part in parts)
      switch (part) {
        'mod' => apple ? 'meta' : 'ctrl',
        'cmd' || 'command' || 'meta' || 'super' => 'meta',
        'control' || 'ctrl' => 'ctrl',
        'option' || 'alt' => 'alt',
        _ => part,
      },
  };
  final String name = key.length == 1
      ? key.toUpperCase()
      : '${key[0].toUpperCase()}${key.substring(1)}';
  if (apple) {
    // Apple's order: Control, Option, Shift, Command.
    const Map<String, String> symbols = <String, String>{
      'ctrl': '⌃',
      'alt': '⌥',
      'shift': '⇧',
      'meta': '⌘',
    };
    return '${<String>[
      for (final String modifier in symbols.keys)
        if (modifiers.contains(modifier)) symbols[modifier]!,
    ].join()}$name';
  }
  const Map<String, String> words = <String, String>{
    'ctrl': 'Ctrl',
    'meta': 'Win',
    'alt': 'Alt',
    'shift': 'Shift',
  };
  return <String>[
    for (final String modifier in words.keys)
      if (modifiers.contains(modifier)) words[modifier]!,
    name,
  ].join('+');
}
