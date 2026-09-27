/// Esc on a page: closes what the page has open, and is otherwise left alone.
///
/// Every page is wrapped in a selection area, and a selection area answers
/// Esc -- the [DismissIntent] every app maps it to -- by hiding its menu. With
/// no menu showing it still reported the key handled. On the web a handled
/// key is one the page called `preventDefault` on, so the browser never saw
/// it: Esc from the page stopped closing the browser's find bar, which is
/// the key a reader presses after Ctrl+F, and stopped reaching anything else
/// the browser does with it.
///
/// The page answers [DismissIntent] beneath the selection area instead. It
/// hides the selection menu when one is showing, hands the intent to
/// whatever answers it above the page -- a dismissible route the page is in,
/// the application's own action -- and otherwise declines it, which leaves
/// the key unhandled and the browser free to act on it. A dialog, a menu or a
/// field with its own answer to Esc is nearer to focus than this and is not
/// affected.
///
/// Not in the barrel: the page shell carries it, as it carries keyboard
/// scrolling, and there is nothing for an application to add.
library;

import 'package:flutter/widgets.dart';

/// The selection menu a page is showing, if it is showing one.
class DVSelectionMenuTracker {
  /// The selection area whose menu is on screen, or null when none is.
  SelectableRegionState? shown;
}

/// Wraps a selection menu so the page knows while it is on screen.
class DVTrackedSelectionMenu extends StatefulWidget {
  const DVTrackedSelectionMenu({
    super.key,
    required this.tracker,
    required this.region,
    required this.child,
  });

  final DVSelectionMenuTracker tracker;
  final SelectableRegionState region;
  final Widget child;

  @override
  State<DVTrackedSelectionMenu> createState() => _DVTrackedSelectionMenuState();
}

class _DVTrackedSelectionMenuState extends State<DVTrackedSelectionMenu> {
  @override
  void initState() {
    super.initState();
    widget.tracker.shown = widget.region;
  }

  @override
  void dispose() {
    if (identical(widget.tracker.shown, widget.region)) {
      widget.tracker.shown = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The page's answer to [DismissIntent], placed inside its selection area.
class DVPageDismissAction extends Action<DismissIntent> {
  DVPageDismissAction({required this.outside, required this.menu});

  /// A context above the selection area: where the intent goes next when the
  /// page has nothing of its own to close.
  final BuildContext Function() outside;

  final DVSelectionMenuTracker menu;

  /// What answers the intent above the page, or null when nothing does.
  Action<DismissIntent>? _above(DismissIntent intent) {
    final BuildContext context = outside();
    if (!context.mounted) return null;
    return Actions.maybeFind<DismissIntent>(context, intent: intent);
  }

  /// Whether focus is in a text field that is composing: an input method's
  /// Esc cancels the composition, and the key is the input method's.
  static bool get _composing {
    final BuildContext? focused = FocusManager.instance.primaryFocus?.context;
    final EditableTextState? field = focused == null
        ? null
        : (focused is StatefulElement && focused.state is EditableTextState
              ? focused.state as EditableTextState
              : focused.findAncestorStateOfType<EditableTextState>());
    final TextRange? composing = field?.textEditingValue.composing;
    return composing != null && composing.isValid && !composing.isCollapsed;
  }

  @override
  bool isEnabled(DismissIntent intent) {
    if (_composing) return false;
    if (menu.shown?.mounted ?? false) return true;
    return _above(intent)?.isEnabled(intent) ?? false;
  }

  @override
  bool consumesKey(DismissIntent intent) {
    if (menu.shown?.mounted ?? false) return true;
    return _above(intent)?.consumesKey(intent) ?? false;
  }

  @override
  Object? invoke(DismissIntent intent) {
    final SelectableRegionState? region = menu.shown;
    if (region != null && region.mounted) {
      // As the selection area does: the menu goes, the selection stays.
      region.hideToolbar(false);
      return null;
    }
    final Action<DismissIntent>? above = _above(intent);
    if (above == null) return null;
    final BuildContext context = outside();
    return Actions.of(context).invokeAction(above, intent, context);
  }
}
