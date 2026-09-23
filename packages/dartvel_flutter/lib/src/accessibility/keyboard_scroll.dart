/// Keyboard scrolling on every page, wherever a keyboard can reach one.
///
/// The arrow keys, Page Up, Page Down, Home, End and the space bar scroll a
/// document in every browser and every document reader. On a Flutter page
/// they do nothing until the scrollable itself holds focus, and on a page
/// somebody has just opened nothing does -- so dartvel.dev shipped with a
/// home page no key would move.
///
/// It is not a web question, which is why this is not behind a flag or a
/// platform check. A Bluetooth keyboard on Android, a presenter clicker
/// paired to an iPhone -- those send Page Up and Page Down, and nothing else
/// -- and a TV remote all produce these keys.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Scrolls the page beneath it when the keys a reader expects are pressed.
///
/// Sits above the page body, so a control that wants a key gets it first:
/// Flutter dispatches from whatever holds focus upwards, and this is an
/// ancestor of everything on the page. A text field keeps its arrows, a
/// slider keeps its arrows, a menu keeps its arrows, and what is left over
/// reaches here.
///
/// The arrows are the one set that is shared. When a control has focus they
/// belong to it, or to moving focus between controls on a remote; when
/// nothing does they scroll, which is what a browser does with them. The
/// others belong to the page whatever has focus, because no control uses
/// them for anything else.
class DVKeyboardScroll extends StatefulWidget {
  const DVKeyboardScroll({super.key, required this.child});

  final Widget child;

  /// How far one arrow press moves: about three lines of body text, which is
  /// what a browser scrolls and slow enough to read past.
  static const double lineStep = 60;

  /// How much of the old screen a page turn keeps. A turn that shows no line
  /// twice loses the reader's place.
  static const double pageOverlap = 0.12;

  @override
  State<DVKeyboardScroll> createState() => _DVKeyboardScrollState();
}

class _DVKeyboardScrollState extends State<DVKeyboardScroll> {
  /// Holds focus while nothing on the page does, so the page gets the keys
  /// at all. Out of the tab order: the first Tab belongs to the first link,
  /// not to the page.
  final FocusNode _node = FocusNode(
    debugLabel: 'DVKeyboardScroll',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    // autofocus only applies the first time this builds. Focus can afterwards
    // end up on nothing at all -- a right-click opens the browser's menu and
    // hands focus back to nobody, and a click on a paragraph focuses nothing
    // either -- and from then on the page answered no key. The reader had to
    // find a link to click before scrolling worked again.
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    _node.dispose();
    super.dispose();
  }

  /// Takes the keys back when nothing else wants them.
  ///
  /// Only when focus has landed nowhere. Something a reader is using -- a
  /// text field, a link, a button -- keeps it, because a page that snatched
  /// focus back would take the reader out of what they were typing in.
  void _focusChanged() {
    if (!mounted || !_node.canRequestFocus) return;
    final FocusNode? focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused is FocusScopeNode) {
      _node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: _node,
        autofocus: true,
        onKeyEvent: _onKey,
        child: widget.child,
      );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // A held key repeats, and a reader holding Page Down expects to keep
    // moving; a key coming up is not a press.
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final ScrollPosition? position = _positionFor(event.logicalKey);
    if (position == null) return KeyEventResult.ignored;
    final double? target = _targetFor(event.logicalKey, position);
    if (target == null) return KeyEventResult.ignored;
    final double clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (clamped == position.pixels) {
      // Already at that end. Handled anyway, so the key does not fall
      // through to focus traversal and jump somewhere off screen.
      return KeyEventResult.handled;
    }
    unawaited(position.animateTo(
      clamped,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    ));
    return KeyEventResult.handled;
  }

  /// Where [key] wants to go, or null when this is not a key for the page.
  double? _targetFor(LogicalKeyboardKey key, ScrollPosition position) {
    final bool shift = HardwareKeyboard.instance.isShiftPressed;
    // A page turn keeps a strip of the old screen, so the reader's eye has
    // somewhere to land.
    final double screen =
        position.viewportDimension * (1 - DVKeyboardScroll.pageOverlap);
    return switch (key) {
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.arrowRight =>
        position.pixels + DVKeyboardScroll.lineStep,
      LogicalKeyboardKey.arrowUp ||
      LogicalKeyboardKey.arrowLeft =>
        position.pixels - DVKeyboardScroll.lineStep,
      LogicalKeyboardKey.pageDown => position.pixels + screen,
      LogicalKeyboardKey.pageUp => position.pixels - screen,
      // The browser's space bar: down a screen, and back up with Shift.
      LogicalKeyboardKey.space =>
        position.pixels + (shift ? -screen : screen),
      LogicalKeyboardKey.home => position.minScrollExtent,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
  }

  /// The scroll position [key] should move, or null when nothing on the page
  /// scrolls that way or the key is not the page's to take.
  ScrollPosition? _positionFor(LogicalKeyboardKey key) {
    final Axis? axis = switch (key) {
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.arrowUp ||
      LogicalKeyboardKey.pageDown ||
      LogicalKeyboardKey.pageUp ||
      LogicalKeyboardKey.space ||
      LogicalKeyboardKey.home ||
      LogicalKeyboardKey.end =>
        Axis.vertical,
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.arrowRight =>
        Axis.horizontal,
      _ => null,
    };
    if (axis == null) return null;
    if (_isArrow(key) && !_nothingElseHasFocus) return null;
    // The page's own axis first; a page that only scrolls sideways still
    // answers Page Down, which is the key a clicker sends.
    return _scrollable(axis) ?? _scrollable(_other(axis));
  }

  static bool _isArrow(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;

  static Axis _other(Axis axis) =>
      axis == Axis.vertical ? Axis.horizontal : Axis.vertical;

  /// Whether the arrows are the page's: nothing on it has taken focus.
  ///
  /// A focused control owns its arrows -- a text field moves its caret, a
  /// slider its value, a remote moves focus to the next control. Scrolling
  /// the page underneath any of those is the wrong answer, and it is the
  /// answer a shortcut registered at the top of the application gives.
  bool get _nothingElseHasFocus =>
      identical(FocusManager.instance.primaryFocus, _node);

  /// The first scrollable on the page along [axis] that has been laid out.
  ///
  /// Found by walking down from here rather than read from a
  /// [PrimaryScrollController]: a page's own `SingleChildScrollView` attaches
  /// to the primary controller only on the mobile platforms and only when it
  /// was given no controller of its own, so reading that would answer null
  /// on the web -- where the bug was found -- and on every page that passed
  /// a controller.
  ScrollPosition? _scrollable(Axis axis) {
    ScrollPosition? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final ScrollableState scrollable = element.state as ScrollableState;
        if (scrollable.axisDirection.axis() == axis) {
          final ScrollPosition position = scrollable.position;
          if (position.hasContentDimensions &&
              position.maxScrollExtent > position.minScrollExtent) {
            found = position;
            return;
          }
        }
      }
      element.visitChildren(visit);
    }

    // Not this element itself: it is the Focus, and the page is below it.
    context.visitChildElements(visit);
    return found;
  }
}

extension on AxisDirection {
  Axis axis() => switch (this) {
        AxisDirection.up || AxisDirection.down => Axis.vertical,
        AxisDirection.left || AxisDirection.right => Axis.horizontal,
      };
}
