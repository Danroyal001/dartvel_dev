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
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../../dartvel_flutter.dart' show DVMenuItem;

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

  void _openAt(Offset local) => _controller.open(position: local);

  void _openFromKeyboard() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    _openAt(box == null ? Offset.zero : box.size.center(Offset.zero));
  }

  void _choose(String id) {
    _controller.close();
    widget.onSelected(id);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bool menuKey = event.logicalKey == LogicalKeyboardKey.contextMenu;
    final bool shiftF10 = event.logicalKey == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed;
    if (!menuKey && !shiftF10) return KeyEventResult.ignored;
    _openFromKeyboard();
    return KeyEventResult.handled;
  }

  List<Widget> _entries(List<DVMenuItem> items, TargetPlatform platform) => <Widget>[
        for (final DVMenuItem item in items)
          if (item.children.isNotEmpty)
            SubmenuButton(
              menuChildren: _entries(item.children, platform),
              child: Text(item.label),
            )
          else
            MenuItemButton(
              onPressed: item.enabled ? () => _choose(item.id) : null,
              trailingIcon: item.shortcut == null
                  ? null
                  : Text(dvShortcutLabel(item.shortcut!, platform)),
              child: Text(item.label),
            ),
      ];

  /// Every enabled leaf, for a screen reader: it has no pointer to open the
  /// menu with, so the items are the element's own actions.
  Map<CustomSemanticsAction, VoidCallback> _actions(List<DVMenuItem> items) =>
      <CustomSemanticsAction, VoidCallback>{
        for (final DVMenuItem item in items)
          if (item.children.isNotEmpty)
            ..._actions(item.children)
          else if (item.enabled)
            CustomSemanticsAction(label: item.label): () => widget.onSelected(item.id),
      };

  @override
  Widget build(BuildContext context) {
    final TargetPlatform platform = Theme.of(context).platform;
    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      menuChildren: _entries(widget.items, platform),
      child: Focus(
        onKeyEvent: _onKey,
        child: Semantics(
          customSemanticsActions: _actions(widget.items),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (TapUpDetails details) => _openAt(details.localPosition),
            onLongPressStart: (LongPressStartDetails details) => _openAt(details.localPosition),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// [keys] (`mod+shift+r`) as the platform writes a shortcut: `⇧⌘R` on Apple
/// platforms, `Ctrl+Shift+R` elsewhere. `mod` is Command on Apple platforms
/// and Control everywhere else, as in DVShortcutScope.
String dvShortcutLabel(String keys, TargetPlatform platform) {
  final bool apple = platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
  final List<String> parts = keys.toLowerCase().split('+').map((String part) => part.trim()).toList();
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
  final String name = key.length == 1 ? key.toUpperCase() : '${key[0].toUpperCase()}${key.substring(1)}';
  if (apple) {
    // Apple's order: Control, Option, Shift, Command.
    const Map<String, String> symbols = <String, String>{'ctrl': '⌃', 'alt': '⌥', 'shift': '⇧', 'meta': '⌘'};
    return '${<String>[for (final String modifier in symbols.keys) if (modifiers.contains(modifier)) symbols[modifier]!].join()}$name';
  }
  const Map<String, String> words = <String, String>{'ctrl': 'Ctrl', 'meta': 'Win', 'alt': 'Alt', 'shift': 'Shift'};
  return <String>[for (final String modifier in words.keys) if (modifiers.contains(modifier)) words[modifier]!, name].join('+');
}
