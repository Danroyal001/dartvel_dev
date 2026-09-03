// Switch control and hardware-key navigation.
//
// A kiosk or an embedded device is often driven by something other than a
// touchscreen: one or two switches, a TV remote's D-pad, a keypad. Switch
// control turns a page into something one or two keys can drive -- one steps
// focus through it in traversal order, another activates what is focused,
// and a timer can do the stepping for a single-switch user. Hardware-key
// navigation maps a remote's D-pad and select key onto focus and activation
// with nothing switched on. Kiosk blocks escape, never access: the keys this
// needs are exempt from any hardware-key block, and [DVAccessibilityKeys]
// says which they are.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether switch control is on. One per application, so the generated
/// toggle on an attract route and every [DVSwitchControl] on every page agree.
class DVSwitchControlState extends ChangeNotifier {
  bool _enabled = false;

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  void toggle() => enabled = !enabled;

  /// Off, as at boot. For tests.
  void reset() => enabled = false;
}

/// Which keys are the switches.
///
/// Space and Enter by default: the two a switch interface most often emits,
/// and the two a keyboard user already expects to mean "next" and "go".
class DVSwitchControlSettings {
  final LogicalKeyboardKey next;
  final LogicalKeyboardKey select;

  /// A third switch, for stepping back. Optional: one- and two-switch users
  /// have none.
  final LogicalKeyboardKey? previous;

  const DVSwitchControlSettings({
    this.next = LogicalKeyboardKey.space,
    this.select = LogicalKeyboardKey.enter,
    this.previous,
  });
}

/// Makes [child] drivable by one or two switches while switch control is on.
///
/// Focus steps through the subtree in traversal order and wraps; activating
/// is an [ActivateIntent] on the focused widget, which is what Enter does to
/// a button anyway. With [autoScan] set, focus steps on that interval so a
/// single switch -- the select one -- is enough. Off, the keys are left to
/// the page and an ordinary keyboard user is not hijacked.
class DVSwitchControl extends StatefulWidget {
  final Widget child;
  final DVSwitchControlSettings settings;
  final Duration? autoScan;

  const DVSwitchControl({
    super.key,
    required this.child,
    DVSwitchControlSettings? settings,
    this.autoScan,
  }) : settings = settings ?? const DVSwitchControlSettings();

  @override
  State<DVSwitchControl> createState() => _DVSwitchControlState();
}

class _DVSwitchControlState extends State<DVSwitchControl> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'DVSwitchControl');
  Timer? _timer;

  DVSwitchControlState get _state => DVAccessibilitySwitchControl.state;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onStateChanged);
    _onStateChanged();
  }

  @override
  void didUpdateWidget(DVSwitchControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoScan != widget.autoScan) _onStateChanged();
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _timer?.cancel();
    _scope.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    _timer?.cancel();
    _timer = null;
    final Duration? every = widget.autoScan;
    if (_state.enabled && every != null) {
      _timer = Timer.periodic(every, (_) => _step(forward: true));
    }
  }

  void _step({required bool forward}) {
    if (forward) {
      _scope.nextFocus();
    } else {
      _scope.previousFocus();
    }
  }

  void _activate() => _dvActivateFocused(_scope);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_state.enabled || event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    final DVSwitchControlSettings s = widget.settings;
    if (key == s.next) {
      _step(forward: true);
      return KeyEventResult.handled;
    }
    if (key == s.previous) {
      _step(forward: false);
      return KeyEventResult.handled;
    }
    if (key == s.select) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => FocusScope(
        node: _scope,
        autofocus: true,
        onKeyEvent: _onKey,
        child: widget.child,
      );
}

/// The control that has focus inside [scope], or null when focus rests on a
/// scope node -- nothing is focused yet, or a nested scope is. Read from the
/// focus manager rather than the scope's focusedChild, which for a nested
/// scope is that scope and not the control inside it.
FocusNode? _dvFocusedControl(FocusScopeNode scope) {
  final FocusNode? primary = FocusManager.instance.primaryFocus;
  if (primary == null || primary is FocusScopeNode) return null;
  if (!scope.hasFocus) return null;
  return primary;
}

/// An [ActivateIntent] on the focused control: what Enter does to a button.
void _dvActivateFocused(FocusScopeNode scope) {
  final BuildContext? context = _dvFocusedControl(scope)?.context;
  if (context == null) return;
  Actions.maybeInvoke(context, const ActivateIntent());
}

/// Maps a remote's or keypad's hardware keys onto focus and activation, with
/// nothing switched on: the D-pad moves focus in that direction (the first
/// press lands on the first control), and select, Enter, or a gamepad's A
/// activate what is focused.
class DVHardwareKeys extends StatefulWidget {
  final Widget child;

  const DVHardwareKeys({super.key, required this.child});

  @override
  State<DVHardwareKeys> createState() => _DVHardwareKeysState();
}

class _DVHardwareKeysState extends State<DVHardwareKeys> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'DVHardwareKeys');

  static final Map<LogicalKeyboardKey, TraversalDirection> _directions =
      <LogicalKeyboardKey, TraversalDirection>{
    LogicalKeyboardKey.arrowUp: TraversalDirection.up,
    LogicalKeyboardKey.arrowDown: TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft: TraversalDirection.left,
    LogicalKeyboardKey.arrowRight: TraversalDirection.right,
  };

  static final Set<LogicalKeyboardKey> _activators = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    final TraversalDirection? direction = _directions[key];
    if (direction != null) {
      final FocusNode? current = _dvFocusedControl(_scope);
      if (current == null) {
        _scope.nextFocus();
      } else if (!current.focusInDirection(direction)) {
        // Nothing that way. Stay put rather than jump somewhere surprising.
        return KeyEventResult.handled;
      }
      return KeyEventResult.handled;
    }
    if (_activators.contains(key)) {
      _dvActivateFocused(_scope);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => FocusScope(
        node: _scope,
        autofocus: true,
        onKeyEvent: _onKey,
        child: widget.child,
      );
}

/// The toggle an attract route can carry: switch control on or off.
class DVAccessibilityToggle extends StatelessWidget {
  const DVAccessibilityToggle({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: DVAccessibilitySwitchControl.state,
        builder: (BuildContext context, Widget? _) {
          final bool on = DVAccessibilitySwitchControl.state.enabled;
          return Semantics(
            button: true,
            toggled: on,
            label: 'Switch control',
            child: GestureDetector(
              key: const ValueKey<String>('dv-accessibility-toggle'),
              behavior: HitTestBehavior.opaque,
              onTap: DVAccessibilitySwitchControl.state.toggle,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Switch control: ${on ? 'on' : 'off'}'),
              ),
            ),
          );
        },
      );
}

/// The keys accessibility needs, which a kiosk's hardware-key block must let
/// through. Kiosk blocks escape, never access.
class DVAccessibilityKeys {
  DVAccessibilityKeys._();

  /// Stepping, activating and moving: what switch control, a screen reader's
  /// navigation and a D-pad need.
  static final Set<LogicalKeyboardKey> navigation = <LogicalKeyboardKey>{
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
  };

  static final Set<LogicalKeyboardKey> _shifts = <LogicalKeyboardKey>{
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  /// The platform's own accessibility shortcut, which toggles its screen
  /// reader or accessibility menu: Super+Alt+S on GNOME, Win+Ctrl+Enter for
  /// Narrator, Cmd+F5 for VoiceOver. Chrome OS and Android have theirs
  /// outside the keyboard.
  static Set<LogicalKeyboardKey> get platformShortcut {
    if (kIsWeb) return _gnome;
    if (Platform.isWindows) {
      return <LogicalKeyboardKey>{
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.enter,
      };
    }
    if (Platform.isMacOS) {
      return <LogicalKeyboardKey>{
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.f5,
      };
    }
    return _gnome;
  }

  static final Set<LogicalKeyboardKey> _gnome = <LogicalKeyboardKey>{
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.keyS,
  };

  /// Whether [pressed] -- the keys down together -- is one accessibility
  /// needs: a navigation key, with or without Shift, or the platform's
  /// accessibility shortcut. Anything with another modifier is not, however
  /// harmless: Alt+Tab is how a kiosk is escaped.
  static bool isExempt(Set<LogicalKeyboardKey> pressed) {
    if (pressed.isEmpty) return false;
    if (setEquals(pressed, platformShortcut)) return true;
    final Set<LogicalKeyboardKey> unshifted = pressed.difference(_shifts);
    return unshifted.isNotEmpty && navigation.containsAll(unshifted);
  }
}

/// The one [DVSwitchControlState], reached as `DV.Accessibility.switchControl`.
class DVAccessibilitySwitchControl {
  DVAccessibilitySwitchControl._();

  static final DVSwitchControlState state = DVSwitchControlState();
}
