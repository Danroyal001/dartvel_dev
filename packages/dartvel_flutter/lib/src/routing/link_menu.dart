/// A link's right-click menu, wherever the link is.
///
/// The menu used to be one of the page shell's selection-menu items: a link
/// recorded that it was right-clicked and the selection area's menu asked.
/// A link with no selection area above it -- the 404 page the router's error
/// builder draws, a page with selection off, a kiosk -- showed its hover
/// preview and no menu at all, because the browser's own menu is off so that
/// Flutter's can show. A link now opens the menu itself unless a
/// [DVLinkMenuScope] above it says an enclosing menu will.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/browser_menu.dart' show DVBrowserMenu;
import 'nav_link.dart' show DVLinkOpener, DVPressedLinkTarget;

/// Marks a subtree whose own right-click menu offers the link items, so a
/// link inside it leaves the menu to that.
class DVLinkMenuScope extends InheritedWidget {
  const DVLinkMenuScope({super.key, required super.child});

  /// Whether a menu above [context] answers a right-click on a link.
  static bool covers(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DVLinkMenuScope>() != null;

  @override
  bool updateShouldNotify(DVLinkMenuScope oldWidget) => false;
}

/// What a right-click on a link to [link] offers, the same in every menu.
///
/// [close] hides the menu the items are in, before the item acts.
List<ContextMenuButtonItem> dvLinkMenuItems(
  String link, {
  required VoidCallback close,
}) => <ContextMenuButtonItem>[
  ContextMenuButtonItem(
    label: 'Open in a new tab',
    onPressed: () {
      close();
      DVPressedLinkTarget.clear();
      DVLinkOpener.open(link, newTab: true);
    },
  ),
  ContextMenuButtonItem(
    label: 'Copy link address',
    onPressed: () {
      close();
      DVPressedLinkTarget.clear();
      unawaited(Clipboard.setData(ClipboardData(text: link)));
    },
  ),
];

/// The one link menu a link opens for itself, when nothing above it will.
final ContextMenuController _controller = ContextMenuController();

/// Shows the link menu for [link] at [at].
void dvShowLinkMenu(BuildContext context, String link, Offset at) {
  final BuildContext? hintContext = Overlay.maybeOf(
    context,
    rootOverlay: true,
  )?.context;
  _controller.show(
    context: context,
    contextMenuBuilder: (BuildContext menuContext) => TapRegion(
      onTapOutside: (PointerDownEvent event) => dvHideLinkMenu(),
      child: ExcludeFocus(
        child: AdaptiveTextSelectionToolbar.buttonItems(
          anchors: TextSelectionToolbarAnchors(primaryAnchor: at),
          buttonItems: <ContextMenuButtonItem>[
            ...dvLinkMenuItems(link, close: dvHideLinkMenu),
            if (DVBrowserMenu.isWeb)
              ContextMenuButtonItem(
                label: 'More',
                onPressed: () {
                  dvHideLinkMenu();
                  DVBrowserMenu.openNextNative();
                  if (hintContext != null && hintContext.mounted) {
                    DVBrowserMenu.showHint(hintContext, at);
                  }
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Hides the link menu a link opened, if one is open.
void dvHideLinkMenu() => _controller.remove();
