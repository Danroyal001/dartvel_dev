/// From a parsed accelerator to what XGrabKey wants.
///
/// Pure Dart, so it is tested on every host: the FFI around it can only run
/// under an X server. Both halves have quiet failure modes. A keysym name off
/// by a letter -- `Arrow_Up` for `Up` -- resolves to NoSymbol and the grab
/// silently registers nothing. And a grab under exactly the requested mask
/// never fires while Num Lock is on, because Num Lock is a modifier too;
/// every real X application grabs the requested mask together with its Lock
/// and Num Lock variants.
library dartvel.platform.linux.x11_keys;

import '../accelerator.dart';

/// X11 modifier bits, as X.h defines them.
const int dvX11ShiftMask = 1 << 0;
const int dvX11LockMask = 1 << 1;
const int dvX11ControlMask = 1 << 2;
const int dvX11Mod1Mask = 1 << 3; // Alt
const int dvX11Mod2Mask = 1 << 4; // Num Lock, on every common layout
const int dvX11Mod4Mask = 1 << 6; // Super / Meta

/// The names whose Dartvel spelling differs from Xlib's.
///
/// Anything else is passed through as written: Xlib knows thousands of
/// keysyms and this table is only the set where the two disagree.
const Map<String, String> _keysyms = <String, String>{
  'enter': 'Return',
  'return': 'Return',
  'escape': 'Escape',
  'esc': 'Escape',
  'tab': 'Tab',
  'backspace': 'BackSpace',
  'delete': 'Delete',
  'del': 'Delete',
  'insert': 'Insert',
  'home': 'Home',
  'end': 'End',
  'pageup': 'Prior',
  'pagedown': 'Next',
  'arrowup': 'Up',
  'arrowdown': 'Down',
  'arrowleft': 'Left',
  'arrowright': 'Right',
  'up': 'Up',
  'down': 'Down',
  'left': 'Left',
  'right': 'Right',
  'space': 'space',
  'printscreen': 'Print',
  'pause': 'Pause',
  'capslock': 'Caps_Lock',
  'numlock': 'Num_Lock',
};

/// The Xlib keysym name for a [DVAccelerator.key].
String dvX11KeysymName(String key) {
  final String k = key.toLowerCase();
  final String? named = _keysyms[k];
  if (named != null) return named;
  // f1..f24
  final RegExpMatch? fn = RegExp(r'^f(\d{1,2})$').firstMatch(k);
  if (fn != null) return 'F${fn.group(1)}';
  return k;
}

/// The X11 mask for a set of modifiers.
int dvX11ModifierMask(Set<DVModifierKey> modifiers) {
  var mask = 0;
  for (final DVModifierKey m in modifiers) {
    mask |= switch (m) {
      DVModifierKey.shift => dvX11ShiftMask,
      DVModifierKey.control => dvX11ControlMask,
      DVModifierKey.alt => dvX11Mod1Mask,
      DVModifierKey.meta => dvX11Mod4Mask,
    };
  }
  return mask;
}

/// Every mask to grab for one shortcut: the request, and the request with
/// Caps Lock, with Num Lock, and with both.
///
/// Four grabs for one shortcut. Without the variants the shortcut stops
/// working the moment a lock is on, which gets reported as "works on my
/// machine".
Set<int> dvX11GrabMasks(int requested) => <int>{
      requested,
      requested | dvX11LockMask,
      requested | dvX11Mod2Mask,
      requested | dvX11LockMask | dvX11Mod2Mask,
    };

/// Whether an event's [state] is a press of [requested].
///
/// The lock bits are ignored: the event carries whatever locks are on, and
/// matching on them would dispatch a press with Num Lock on to nothing. Every
/// other bit has to agree, or Ctrl+Shift+K fires the Ctrl+K handler.
bool dvX11StateMatches({required int state, required int requested}) {
  const int ignored = dvX11LockMask | dvX11Mod2Mask;
  return (state & ~ignored) == (requested & ~ignored);
}
