import 'dart:async';

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

  const DVTab(this.route, {this.label});

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
    final existing = _tabs.indexOf(tab);
    if (existing != -1) {
      activate(existing);
      return;
    }
    final index = at == null ? _tabs.length : at.clamp(0, _tabs.length);
    _tabs.insert(index, tab);
    if (_activeIndex == -1) {
      _activeIndex = index;
    } else if (index <= _activeIndex) {
      _activeIndex++;
    }
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
class DVTabWorkspace extends StatefulWidget {
  final List<DVTab> initialTabs;
  final DVTabWorkspaceController? controller;

  /// Builds a tab's content. Defaults to the route path, so a workspace is
  /// useful before any page exists.
  final Widget Function(BuildContext context, DVTab tab)? builder;

  const DVTabWorkspace({
    super.key,
    this.initialTabs = const <DVTab>[],
    this.controller,
    this.builder,
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
          _strip(),
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
