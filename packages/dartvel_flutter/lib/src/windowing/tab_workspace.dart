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

/// One tab's place in a workspace: the tab, and the identity its content keeps
/// while it moves between workspaces.
///
/// The key belongs to the entry rather than to the route. Two deliberate tabs
/// on one route are two tabs, and keying their content by route would make the
/// second one retake the first one's element the moment it was selected --
/// showing a half-written form the person had started somewhere else.
class _DVTabEntry {
  _DVTabEntry(this.tab)
      : contentKey = GlobalKey(debugLabel: 'dv-tab ${tab.route.path}');

  final DVTab tab;

  /// What makes a re-dock a handover rather than a re-creation.
  ///
  /// The same key arriving in another workspace inside one frame reparents the
  /// live element: its `State`, its controllers, its scroll positions and its
  /// in-flight requests are the same objects afterwards, because nothing was
  /// built again.
  final GlobalKey contentKey;
}

/// The state behind a tab strip: order, selection, tear-out and adoption.
///
/// Separated from the widget because every rule worth getting right — what
/// happens to the selection when the active tab leaves, whether an emptied
/// workspace closes its window — is state, not painting.
class DVTabWorkspaceController extends ChangeNotifier {
  DVTabWorkspaceController({
    List<DVTab> tabs = const <DVTab>[],
    this.window,
  }) : _entries = <_DVTabEntry>[
          for (final DVTab tab in tabs) _DVTabEntry(tab),
        ] {
    if (_entries.isNotEmpty) _activeIndex = 0;
  }

  final List<_DVTabEntry> _entries;
  int _activeIndex = -1;

  /// The window this workspace lives in, when it is not the main one. An
  /// emptied workspace closes it.
  final DVWindow? window;

  List<DVTab> get tabs => List<DVTab>.unmodifiable(
        _entries.map((_DVTabEntry entry) => entry.tab),
      );

  int get activeIndex => _activeIndex;

  DVTab? get active => _activeEntry?.tab;

  _DVTabEntry? get _activeEntry =>
      _activeIndex >= 0 && _activeIndex < _entries.length
          ? _entries[_activeIndex]
          : null;

  bool get isEmpty => _entries.isEmpty;

  void activate(int index) {
    if (index < 0 || index >= _entries.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// Adds [tab], or activates it when the workspace already holds it.
  ///
  /// Idempotent by route for the same reason `DV.Window.open` is: two tabs
  /// showing one route is not a state anyone asked for.
  void add(DVTab tab, {int? at}) {
    _adopt(_DVTabEntry(tab), at: at);
  }

  /// Takes [entry] -- a tab new to this workspace, or one moving here from
  /// another with its content identity intact.
  ///
  /// Returns whether the entry was taken. False means the workspace already
  /// had a tab on that route and focused it instead, so whatever [entry] was
  /// carrying did not come across.
  bool _adopt(_DVTabEntry entry, {int? at}) {
    if (!entry.tab.duplicate) {
      // By route, not by object. This used to be _tabs.indexOf(tab), and DVTab
      // overrides no ==, so it compared by identity: two DVTab objects naming
      // the same route were never equal and every add appended. A test reusing
      // one instance -- the natural thing to write -- passed either way.
      final int existing = _entries.indexWhere(
          (_DVTabEntry e) => e.tab.route.path == entry.tab.route.path);
      if (existing != -1) {
        activate(existing);
        return false;
      }
    }
    final index = at == null ? _entries.length : at.clamp(0, _entries.length);
    _entries.insert(index, entry);
    // The tab that was added is the one to look at, exactly as adding a route
    // that is already open activates the tab holding it. A workspace that
    // added a tab behind you would be a different rule for the same action,
    // and a tab dragged in from another window would land out of sight.
    //
    // It is also what makes a handover possible at all: only the active tab is
    // built, so a tab that arrived in the background would have its element
    // dropped on the floor rather than reparented.
    _activeIndex = index;
    notifyListeners();
    return true;
  }

  /// Moves a tab within the strip. Works on every target, including ones with
  /// no windowing capability at all — reordering is pure UI.
  void reorder(int from, int to) {
    if (from < 0 || from >= _entries.length) return;
    final target = to.clamp(0, _entries.length - 1);
    if (from == target) return;
    final moving = _entries.removeAt(from);
    _entries.insert(target, moving);
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
  DVTab? removeAt(int index, {DVTabExit reason = DVTabExit.closed}) =>
      _removeEntryAt(index, reason: reason)?.tab;

  _DVTabEntry? _removeEntryAt(int index,
      {DVTabExit reason = DVTabExit.closed}) {
    if (index < 0 || index >= _entries.length) return null;
    final removed = _entries.removeAt(index);
    if (_entries.isEmpty) {
      _activeIndex = -1;
    } else if (index < _activeIndex) {
      _activeIndex--;
    } else if (index == _activeIndex) {
      _activeIndex = index.clamp(0, _entries.length - 1);
    }
    notifyListeners();
    return removed;
  }

  /// Detaches the tab at [index] into its own window.
  ///
  /// Gated on `capability.tearOut`: where it is false the tab does not leave
  /// the strip, because a gesture that silently does nothing is worse than one
  /// that is absent. Returns the window when it happened.
  ///
  /// This is not a handover and does not pretend to be one. The new window
  /// renders the route through the host's route builder, so the tab arrives
  /// built from scratch; what crosses is what was written to the shared store
  /// under `workspace.tab.<path>` just before the window opened. [moveTo] is
  /// the handover, because there the receiving workspace is already on screen
  /// and can take the element itself.
  Future<DVWindow?> tearOut(int index) async {
    if (index < 0 || index >= _entries.length) return null;
    if (!DV.Platform.Window.capability.tearOut) return null;

    final tab = _entries[index].tab;
    final int started = DVWindowManager.performance.mark();
    // Written before the window opens: the new engine reads the store on
    // boot, so a slow start loses nothing.
    await DVWindowManager.shared
        .flushReserved('workspace.tab.${tab.route.path}');
    final opened = await DV.Platform.Window.open(tab.route);
    DVWindowManager.performance.recordTearOutFrom(started, route: tab.route.path);
    removeAt(index, reason: DVTabExit.tornOut);
    await _closeIfEmptied();
    return opened;
  }

  /// Moves the tab at [index] into [destination], reporting how it travelled.
  ///
  /// [DVWindowHandover.sameEngine] means the tab arrived whole: its element is
  /// reparented into the receiving workspace, so the text someone was half way
  /// through typing, the position they had scrolled to, the controllers and
  /// the requests still in flight are the same objects afterwards. That is the
  /// difference between a re-dock and a tab that looks right and is empty.
  ///
  /// [DVWindowHandover.shared] means it did not: [destination] already had a
  /// tab on that route and focused it, so this tab was closed and nothing but
  /// the shared store crossed. Null means [index] named no tab.
  ///
  /// Both workspaces must be on screen. That is not a restriction so much as
  /// what "the same engine" means here: `DVWindowHost` renders every window as
  /// a `View` in one `ViewCollection`, so two windows share a build owner and
  /// an element can move between them -- and a workspace that is not mounted
  /// has no element tree to move into. [moveDestinations] lists the ones that
  /// qualify.
  Future<DVWindowHandover?> moveTo(
    DVTabWorkspaceController destination,
    int index,
  ) async {
    final _DVTabEntry? entry =
        _removeEntryAt(index, reason: DVTabExit.adopted);
    if (entry == null) return null;
    // The receiver takes it before anything is awaited. Both notifications
    // then land in the same frame, which is the entire mechanism: an await in
    // between would put the departure in one frame and the arrival in the
    // next, the element would be unmounted in the gap, and the handover would
    // quietly become a rebuild that still looks correct on screen.
    final bool taken = destination._adopt(entry);
    await _closeIfEmptied();
    return taken ? DVWindowHandover.sameEngine : DVWindowHandover.shared;
  }

  /// The workspaces currently on screen, in the order they were mounted.
  ///
  /// Held as the widget states rather than the controllers so that rebuilding
  /// a workspace elsewhere in the tree -- a new state mounting before the old
  /// one is disposed -- cannot leave a live workspace unregistered.
  static final List<_DVTabWorkspaceState> _mounted = <_DVTabWorkspaceState>[];

  /// Where a tab from this workspace can be moved.
  ///
  /// Only workspaces that are actually on screen: an unmounted controller has
  /// no strip to drop a tab into, and a tab moved somewhere invisible reads to
  /// the person who moved it as a tab that was lost.
  ///
  /// A workspace in another window is offered only where windows share an
  /// engine. Elsewhere the other window is a separate isolate holding no
  /// object this one could hand anything to, and the honest affordance there
  /// is "open in new window" -- the same rule tear-out follows, absent rather
  /// than present and empty.
  List<DVTabWorkspaceController> get moveDestinations {
    final bool acrossWindows = DV.Platform.Window.capability.sameEngine;
    return <DVTabWorkspaceController>[
      for (final _DVTabWorkspaceState state in _mounted)
        if (!identical(state._controller, this) &&
            (acrossWindows || identical(state._controller.window, window)))
          state._controller,
    ];
  }

  /// Whether a tab can be dragged out of this strip and into another window's.
  ///
  /// False everywhere, at the Flutter this ships against. A drag belongs to
  /// the window the pointer went down in: the OS grabs the pointer for that
  /// window until the button comes up, Flutter routes every move to that view,
  /// and the feedback under the cursor is clipped to it -- so no strip in
  /// another window ever sees the gesture, whatever the two windows share.
  /// Nor could Dartvel work out which window the cursor was over: it does not
  /// track where its windows are on screen, deliberately, because on Wayland
  /// there is no window position to track.
  ///
  /// So a cross-window move is an action naming a destination from
  /// [moveDestinations], and it is the arrival that is a real handover. Said
  /// here rather than left to be discovered, because a drag that quietly ends
  /// nowhere is the thing this whole file is trying not to ship.
  bool get offersCrossWindowDrag => false;

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
  void initState() {
    super.initState();
    // On screen, so a tab from another workspace can be moved here.
    DVTabWorkspaceController._mounted.add(this);
  }

  @override
  void dispose() {
    DVTabWorkspaceController._mounted.remove(this);
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
              // Keyed by the tab, not by this workspace and not by the route.
              // A tab that moves takes this key with it, so the workspace
              // receiving it reparents the element that is already built
              // instead of building a second one and throwing the first away.
              child: KeyedSubtree(
                key: _controller._activeEntry!.contentKey,
                child: widget.builder?.call(context, active) ??
                    DVText(active.route.path),
              ),
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

  /// Move and close, as actions: the switchers have no drag, and no strip on
  /// any target has a drag that reaches another window.
  Widget _actions(int index) {
    final int count = _controller.tabs.length;
    final List<DVTabWorkspaceController> destinations =
        _controller.moveDestinations;
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
      // Where the drag cannot go. A tab cannot be dragged into another
      // window's strip at this Flutter -- see
      // DVTabWorkspaceController.offersCrossWindowDrag -- so the move is an
      // action naming the destination. It is the same call the drag would have
      // made, and the tab arrives whole either way.
      for (int d = 0; d < destinations.length; d++)
        action('dv-tab-move-to-$d', 'Move to ${_nameOf(destinations[d])}', () {
          // Not awaited, for the reason the tear-out drop is not: the tab has
          // left this strip by the time the call returns to the event loop,
          // and what the emptied window then does is the window's business.
          unawaited(_controller.moveTo(destinations[d], index));
          setState(() {
            _actionsFor = null;
            if (_focused >= _controller.tabs.length && _focused > 0) _focused--;
          });
        }),
    ], spacing: 4),
    );
  }

  /// What to call a destination in the menu.
  ///
  /// The window's route, because that is the only name a window is guaranteed
  /// to have -- a title is optional and the OS may not have honoured it.
  String _nameOf(DVTabWorkspaceController destination) =>
      destination.window?.route.path ?? 'the main window';

  // --- the strip --------------------------------------------------------------

  Widget _strip() {
    final tabs = _controller.tabs;
    final int? actionsFor = _actionsFor;
    return DVBox.list(<Widget>[
      DVBox.row(<Widget>[
        for (var i = 0; i < tabs.length; i++) _tab(i, tabs[i]),
      ]),
      // The same menu the switchers use, for the same reason: some things a
      // tab can do have no gesture. On a strip that is the cross-window move.
      if (actionsFor != null && actionsFor < tabs.length) _actions(actionsFor),
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
          // Stationary, so the drag recognizer above never claims it.
          onLongPress: () => setState(() => _actionsFor = index),
          child: label,
        ),
      ),
    );
  }
}
