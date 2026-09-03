import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// A tab is a route.
///
/// The same identity a window has, which is what makes tear-out navigation
/// rather than surgery. There is deliberately no `DVTab.widget(...)`: a tab
/// without a route cannot tear out on any separate-engine target, cannot be
/// deep-linked, and cannot be restored.
@immutable
class DVTab {
  final DVRouteTarget route;

  /// Shown in the strip. Defaults to the route's last segment.
  final String? label;

  /// Whether this is a deliberate second tab on a route already open.
  ///
  /// Mirrors `DVWindowOptions.duplicate`. Without it, adding a route the
  /// workspace already holds focuses the tab that holds it.
  final bool duplicate;

  const DVTab(this.route, {this.label, this.duplicate = false});

  String get title {
    final given = label;
    if (given != null && given.isNotEmpty) return given;
    final segments =
        route.path.split('/').where((String s) => s.isNotEmpty).toList();
    return segments.isEmpty ? '/' : segments.last;
  }

  @override
  bool operator ==(Object other) =>
      other is DVTab && other.route.path == route.path;

  @override
  int get hashCode => route.path.hashCode;
}

/// Why a tab left a workspace, so the caller can tell a tear-out from a close.
enum DVTabExit { closed, tornOut, adopted }

/// The state behind a tab strip: order, selection, tear-out and adoption.
///
/// Separated from the widget because every rule worth getting right — what
/// happens to the selection when the active tab leaves, whether an emptied
/// workspace closes its window — is state, not painting.
class DVTabWorkspaceController extends ChangeNotifier {
  DVTabWorkspaceController({
    List<DVTab> tabs = const <DVTab>[],
    this.window,
  }) : _tabs = List<DVTab>.of(tabs) {
    if (_tabs.isNotEmpty) _activeIndex = 0;
  }

  final List<DVTab> _tabs;
  int _activeIndex = -1;

  /// The window this workspace lives in, when it is not the main one. An
  /// emptied workspace closes it.
  final DVWindow? window;

  List<DVTab> get tabs => List<DVTab>.unmodifiable(_tabs);

  int get activeIndex => _activeIndex;

  DVTab? get active =>
      _activeIndex >= 0 && _activeIndex < _tabs.length ? _tabs[_activeIndex] : null;

  bool get isEmpty => _tabs.isEmpty;

  void activate(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Adds [tab], or activates it when the workspace already holds it.
  ///
  /// Idempotent by route for the same reason `DV.Window.open` is: two tabs
  /// showing one route is not a state anyone asked for.
  void add(DVTab tab, {int? at}) {
    if (!tab.duplicate) {
      // By route, not by object. This used to be _tabs.indexOf(tab), and DVTab
      // overrides no ==, so it compared by identity: two DVTab objects naming
      // the same route were never equal and every add appended. A test reusing
      // one instance -- the natural thing to write -- passed either way.
      final int existing =
          _tabs.indexWhere((DVTab t) => t.route.path == tab.route.path);
      if (existing != -1) {
        activate(existing);
        return;
      }
    }
    final index = at == null ? _tabs.length : at.clamp(0, _tabs.length);
    _tabs.insert(index, tab);
    // The tab that was added is the one to look at, exactly as adding a route
    // that is already open activates the tab holding it. A workspace that
    // added a tab behind you would be a different rule for the same action,
    // and a tab dragged in from another window would land out of sight.
    _activeIndex = index;
    notifyListeners();
  }

  /// Moves a tab within the strip. Works on every target, including ones with
  /// no windowing capability at all — reordering is pure UI.
  void reorder(int from, int to) {
    if (from < 0 || from >= _tabs.length) return;
    final target = to.clamp(0, _tabs.length - 1);
    if (from == target) return;
    final moving = _tabs.removeAt(from);
    _tabs.insert(target, moving);
    final wasActive = _activeIndex;
    if (wasActive == from) {
      _activeIndex = target;
    } else if (from < wasActive && target >= wasActive) {
      _activeIndex--;
    } else if (from > wasActive && target <= wasActive) {
      _activeIndex++;
    }
    notifyListeners();
  }

  /// Removes the tab at [index], returning it.
  ///
  /// Selection moves to the neighbour rather than resetting, because a closed
  /// tab should leave the user where they were looking.
  DVTab? removeAt(int index, {DVTabExit reason = DVTabExit.closed}) {
    if (index < 0 || index >= _tabs.length) return null;
    final removed = _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      _activeIndex = -1;
    } else if (index < _activeIndex) {
      _activeIndex--;
    } else if (index == _activeIndex) {
      _activeIndex = index.clamp(0, _tabs.length - 1);
    }
    notifyListeners();
    return removed;
  }

  /// Detaches the tab at [index] into its own window.
  ///
  /// Gated on `capability.tearOut`: where it is false the tab does not leave
  /// the strip, because a gesture that silently does nothing is worse than one
  /// that is absent. Returns the window when it happened.
  Future<DVWindow?> tearOut(int index) async {
    if (index < 0 || index >= _tabs.length) return null;
    if (!DV.Platform.Window.capability.tearOut) return null;

    final tab = _tabs[index];
    // Written before the window opens: the new engine reads the store on
    // boot, so a slow start loses nothing.
    await DVWindowManager.shared
        .flushReserved('workspace.tab.${tab.route.path}');
    final opened = await DV.Platform.Window.open(tab.route);
    removeAt(index, reason: DVTabExit.tornOut);
    await _closeIfEmptied();
    return opened;
  }

  /// Moves a tab into [destination]. Same convergence as a drag between
  /// strips: the receiving workspace adds the route, this one lets it go.
  Future<void> moveTo(DVTabWorkspaceController destination, int index) async {
    final tab = removeAt(index, reason: DVTabExit.adopted);
    if (tab == null) return;
    destination.add(tab);
    await _closeIfEmptied();
  }

  /// A workspace window whose last tab leaves closes itself. This is state
  /// policy rather than a window callback, so tear-out, re-dock and cleanup
  /// are one transition.
  Future<void> _closeIfEmptied() async {
    if (!isEmpty) return;
    final owned = window;
    if (owned != null) await owned.close();
  }

  /// Whether "open in new window" should be offered at all.
  ///
  /// Degrading a call is right; advertising a control that produces a
  /// surprising result is not.
  bool get offersNewWindow => DV.Platform.Window.capability.multiWindow;

  bool get offersTearOut => DV.Platform.Window.capability.tearOut;
}

/// A tab strip and its content, composed from `DVBox` and `DVText`.
///
/// A generated application component in the same sense as `User.Table()`: no
/// new primitive, and every behaviour worth testing lives on the controller.
/// How the tabs are shown.
///
/// A strip with drag on anything with a pointer; on a TV a row of tiles the
/// D-pad moves between; on a watch a stack of tiles to tap. On the
/// switchers there is no drag -- moving or closing a tab is an action on
/// the tab's menu, opened with the remote's menu key or a long press.
enum DVTabPresentation { auto, strip, tv, watch }

/// The presentation for a device.
DVTabPresentation dvTabPresentationFor({required bool isTV, required bool isWatch}) {
  if (isTV) return DVTabPresentation.tv;
  if (isWatch) return DVTabPresentation.watch;
  return DVTabPresentation.strip;
}

class DVTabWorkspace extends StatefulWidget {
  final List<DVTab> initialTabs;
  final DVTabWorkspaceController? controller;

  /// Builds a tab's content. Defaults to the route path, so a workspace is
  /// useful before any page exists.
  final Widget Function(BuildContext context, DVTab tab)? builder;

  /// [DVTabPresentation.auto] follows the device.
  final DVTabPresentation presentation;

  const DVTabWorkspace({
    super.key,
    this.initialTabs = const <DVTab>[],
    this.controller,
    this.builder,
    this.presentation = DVTabPresentation.auto,
  });

  @override
  State<DVTabWorkspace> createState() => _DVTabWorkspaceState();
}

class _DVTabWorkspaceState extends State<DVTabWorkspace> {
  late final DVTabWorkspaceController _controller =
      widget.controller ?? DVTabWorkspaceController(tabs: widget.initialTabs);

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (BuildContext context, Widget? _) {
        final active = _controller.active;
        return DVBox.list(<Widget>[
          switch (_presentation) {
            DVTabPresentation.tv => _switcher(horizontal: true),
            DVTabPresentation.watch => _switcher(horizontal: false),
            _ => _strip(),
          },
          if (active == null)
            const DVText('No tabs open.')
          else
            Expanded(
              child: widget.builder?.call(context, active) ??
                  DVText(active.route.path),
            ),
        ]);
      },
    );
  }

  /// The strip, with drag to reorder and drag out to detach.
  ///
  /// The controller could already do both; nothing in the strip could ask it
  /// to, so the spec's "drag within the strip" and "drag beyond the strip"
  /// were controller calls a test could make and a person could not.
  /// The tile the D-pad is on, and the tile whose actions are open.
  int _focused = 0;
  int? _actionsFor;

  DVTabPresentation get _presentation => widget.presentation == DVTabPresentation.auto
      ? dvTabPresentationFor(isTV: DV.Platform.isTV, isWatch: DV.Platform.isWatch)
      : widget.presentation;

  // --- the switcher ---------------------------------------------------------

  KeyEventResult _onSwitcherKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final int count = _controller.tabs.length;
    if (count == 0) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focused = (_focused + 1) % count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focused = (_focused - 1 + count) % count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _controller.activate(_focused);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu) {
      setState(() => _actionsFor = _focused);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_actionsFor == null) return KeyEventResult.ignored;
      setState(() => _actionsFor = null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _switcher({required bool horizontal}) {
    final List<DVTab> tabs = _controller.tabs;
    if (_focused >= tabs.length) _focused = tabs.isEmpty ? 0 : tabs.length - 1;
    final List<Widget> tiles = <Widget>[
      for (int i = 0; i < tabs.length; i++) _tile(i, tabs[i], horizontal: horizontal),
    ];
    final Widget laid = horizontal ? DVBox.row(tiles, spacing: 8) : DVBox.list(tiles, spacing: 8);
    final int? actionsFor = _actionsFor;
    return Focus(
      autofocus: horizontal,
      onKeyEvent: _onSwitcherKey,
      child: DVBox.list(<Widget>[
        laid,
        if (actionsFor != null && actionsFor < tabs.length) _actions(actionsFor),
      ], spacing: 8),
    );
  }

  Widget _tile(int index, DVTab tab, {required bool horizontal}) {
    final bool active = index == _controller.activeIndex;
    final bool focused = horizontal && index == _focused;
    return GestureDetector(
      key: ValueKey<String>('dv-tab-tile-$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.activate(index),
      onLongPress: () => setState(() => _actionsFor = index),
      child: DVText(tab.title).modifier(
        const DVModifier()
            .padding(12)
            .fontSize(horizontal ? 18 : 16)
            .fontWeight(active ? FontWeight.bold : FontWeight.normal)
            .backgroundColor(focused ? const Color(0x336C4BF4) : const Color(0x00000000)),
      ),
    );
  }

  /// Move and close, as actions: the switchers have no drag.
  Widget _actions(int index) {
    final int count = _controller.tabs.length;
    Widget action(String key, String label, VoidCallback? onTap) => GestureDetector(
          key: ValueKey<String>(key),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DVText(label).modifier(const DVModifier().padding(10)),
        );
    return KeyedSubtree(
      key: const ValueKey<String>('dv-tab-actions'),
      child: DVBox.row(<Widget>[
      // The menu follows the tab it moved, so moving twice is two taps.
      action('dv-tab-move-left', 'Move left', index == 0 ? null : () {
        _controller.reorder(index, index - 1);
        setState(() {
          _actionsFor = index - 1;
          _focused = index - 1;
        });
      }),
      action('dv-tab-move-right', 'Move right', index >= count - 1 ? null : () {
        _controller.reorder(index, index + 1);
        setState(() {
          _actionsFor = index + 1;
          _focused = index + 1;
        });
      }),
      action('dv-tab-close', 'Close', () {
        _controller.removeAt(index);
        setState(() {
          _actionsFor = null;
          if (_focused >= _controller.tabs.length && _focused > 0) _focused--;
        });
      }),
    ], spacing: 4),
    );
  }

  // --- the strip --------------------------------------------------------------

  Widget _strip() {
    final tabs = _controller.tabs;
    return DVBox.row(<Widget>[
      for (var i = 0; i < tabs.length; i++) _tab(i, tabs[i]),
    ]);
  }

  Widget _tab(int index, DVTab tab) {
    final Widget label = DVText(tab.title).modifier(
      const DVModifier().padding(8).fontWeight(
            index == _controller.activeIndex
                ? FontWeight.bold
                : FontWeight.normal,
          ),
    );

    return DragTarget<int>(
      // A tab is not a drop target for itself: accepting would make a drag
      // that went nowhere look like a reorder.
      onWillAcceptWithDetails: (DragTargetDetails<int> details) =>
          details.data != index,
      onAcceptWithDetails: (DragTargetDetails<int> details) =>
          _controller.reorder(details.data, index),
      builder: (BuildContext context, _, __) => Draggable<int>(
        data: index,
        // Dropped where no tab accepted it, which is what "beyond the strip"
        // means. A DragTarget around the strip cannot see this: a drop below
        // the strip is outside its hit area entirely, so nothing fires.
        onDraggableCanceled: (_, __) {
          // Gated, and absent rather than inert: where tear-out is
          // unavailable the drop does nothing and the tab stays where it was.
          if (!DV.Platform.Window.capability.tearOut) return;
          // Not awaited: the drop callback is synchronous and the tab leaves
          // the strip as soon as the controller notifies. The window it opens
          // is the platform's business.
          unawaited(_controller.tearOut(index));
        },
        // Shown under the pointer while dragging. Without it the tab appears
        // to stay put and the gesture reads as unresponsive. No Material
        // wrapper: this file is Material-free by design, and DVText carries
        // its own style.
        feedback: Opacity(opacity: 0.9, child: label),
        childWhenDragging: Opacity(opacity: 0.4, child: label),
        child: GestureDetector(
          key: ValueKey<String>('dv-tab-${tab.route.path}'),
          onTap: () => _controller.activate(index),
          child: label,
        ),
      ),
    );
  }
}
