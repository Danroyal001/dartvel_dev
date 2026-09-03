// From a parsed accelerator to what XGrabKey wants.
//
// X11 grabs a keycode under a modifier mask, and both halves have quiet
// failure modes. A keysym name that is off by a letter -- 'Arrow_Up' for
// 'Up' -- resolves to NoSymbol and the grab silently registers nothing. And a
// grab under exactly the requested mask never fires while Num Lock is on,
// because Num Lock is a modifier too: every real X application grabs the
// requested mask together with its Lock and Num Lock variants.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/platform/linux/x11_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keysym names', () {
    test('a letter is itself, lower case', () {
      expect(dvX11KeysymName('k'), 'k');
    });

    test('a digit is itself', () {
      expect(dvX11KeysymName('5'), '5');
    });

    test('function keys are upper-case F', () {
      expect(dvX11KeysymName('f5'), 'F5');
      expect(dvX11KeysymName('f12'), 'F12');
    });

    test('the names Xlib actually uses', () {
      // These are the ones a typo turns into NoSymbol.
      expect(dvX11KeysymName('space'), 'space');
      expect(dvX11KeysymName('enter'), 'Return');
      expect(dvX11KeysymName('return'), 'Return');
      expect(dvX11KeysymName('escape'), 'Escape');
      expect(dvX11KeysymName('esc'), 'Escape');
      expect(dvX11KeysymName('tab'), 'Tab');
      expect(dvX11KeysymName('backspace'), 'BackSpace');
      expect(dvX11KeysymName('delete'), 'Delete');
      expect(dvX11KeysymName('arrowup'), 'Up');
      expect(dvX11KeysymName('arrowdown'), 'Down');
      expect(dvX11KeysymName('arrowleft'), 'Left');
      expect(dvX11KeysymName('arrowright'), 'Right');
      expect(dvX11KeysymName('home'), 'Home');
      expect(dvX11KeysymName('end'), 'End');
      expect(dvX11KeysymName('pageup'), 'Prior');
      expect(dvX11KeysymName('pagedown'), 'Next');
      expect(dvX11KeysymName('insert'), 'Insert');
    });

    test('an unknown name is passed through, so Xlib decides', () {
      // Xlib knows thousands of keysyms; the table above is the set whose
      // Dartvel spelling differs from Xlib's. Anything else goes as written.
      expect(dvX11KeysymName('plus'), 'plus');
    });
  });

  group('modifier masks', () {
    test('each modifier is its X11 bit', () {
      expect(dvX11ModifierMask(<DVModifierKey>{DVModifierKey.shift}), 1 << 0);
      expect(dvX11ModifierMask(<DVModifierKey>{DVModifierKey.control}), 1 << 2);
      expect(dvX11ModifierMask(<DVModifierKey>{DVModifierKey.alt}), 1 << 3);
      expect(dvX11ModifierMask(<DVModifierKey>{DVModifierKey.meta}), 1 << 6);
    });

    test('they combine', () {
      expect(
        dvX11ModifierMask(<DVModifierKey>{DVModifierKey.control, DVModifierKey.shift}),
        (1 << 2) | (1 << 0),
      );
    });

    test('no modifier is zero', () {
      expect(dvX11ModifierMask(<DVModifierKey>{}), 0);
    });
  });

  group('the masks actually grabbed', () {
    test('the requested mask, plus its Lock and Num Lock variants', () {
      // Four grabs for one shortcut. Without the variants the shortcut stops
      // working the moment Caps Lock or Num Lock is on, which is the sort of
      // thing that gets reported as "works on my machine".
      const int ctrl = 1 << 2;
      const int lock = 1 << 1;
      const int numLock = 1 << 4;
      expect(
        dvX11GrabMasks(ctrl),
        <int>{ctrl, ctrl | lock, ctrl | numLock, ctrl | lock | numLock},
      );
    });

    test('with no modifier, the same four', () {
      expect(dvX11GrabMasks(0), <int>{0, 1 << 1, 1 << 4, (1 << 1) | (1 << 4)});
    });

    test('a pressed state matches its grab regardless of the lock bits', () {
      // When the event arrives its state carries whatever locks are on. The
      // match is on the requested bits only, or a press with Num Lock on is
      // dispatched to nothing.
      const int ctrl = 1 << 2;
      expect(dvX11StateMatches(state: ctrl | (1 << 4), requested: ctrl), isTrue);
      expect(dvX11StateMatches(state: ctrl | (1 << 1), requested: ctrl), isTrue);
      expect(dvX11StateMatches(state: ctrl, requested: ctrl), isTrue);
    });

    test('but not with a different real modifier', () {
      // Ctrl+Shift+K pressed must not fire the Ctrl+K handler.
      const int ctrl = 1 << 2;
      const int shift = 1 << 0;
      expect(dvX11StateMatches(state: ctrl | shift, requested: ctrl), isFalse);
      expect(dvX11StateMatches(state: ctrl, requested: ctrl | shift), isFalse);
    });
  });
}
