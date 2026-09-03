// Reading an accelerator string, before any platform sees it.
//
// A global shortcut arrives as text -- 'Ctrl+K', 'CmdOrCtrl+Shift+P' -- and
// every native binding has to turn it into the same modifiers and the same
// key. Parsed once here rather than once per platform, or the Linux and
// Windows bindings drift on what 'Cmd' means and a shortcut works on one and
// not the other with no error anywhere.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsing', () {
    test('modifiers and the key come apart', () {
      final DVAccelerator a = DVAccelerator.parse('Ctrl+Shift+K');
      expect(a.modifiers, <DVModifierKey>{DVModifierKey.control, DVModifierKey.shift});
      expect(a.key, 'k');
    });

    test('case and spacing do not matter', () {
      expect(DVAccelerator.parse(' ctrl + k ').key, 'k');
      expect(DVAccelerator.parse('CTRL+K').modifiers, contains(DVModifierKey.control));
    });

    test('a key alone is a shortcut, though a bad one', () {
      // Allowed: some kiosk hardware has dedicated keys. But it is what a
      // typo produces, so it is not silently treated as a modifier.
      final DVAccelerator a = DVAccelerator.parse('F5');
      expect(a.modifiers, isEmpty);
      expect(a.key, 'f5');
    });

    test('the platform-neutral names resolve', () {
      expect(DVAccelerator.parse('Cmd+K').modifiers, contains(DVModifierKey.meta));
      expect(DVAccelerator.parse('Super+K').modifiers, contains(DVModifierKey.meta));
      expect(DVAccelerator.parse('Win+K').modifiers, contains(DVModifierKey.meta));
      expect(DVAccelerator.parse('Option+K').modifiers, contains(DVModifierKey.alt));
      expect(DVAccelerator.parse('Control+K').modifiers, contains(DVModifierKey.control));
    });

    test('CmdOrCtrl is the primary modifier for the platform', () {
      // The one place an accelerator string is allowed to mean different
      // things on different machines, and it says so in its name.
      expect(DVAccelerator.parse('CmdOrCtrl+K', primaryIsMeta: true).modifiers,
          <DVModifierKey>{DVModifierKey.meta});
      expect(DVAccelerator.parse('CmdOrCtrl+K', primaryIsMeta: false).modifiers,
          <DVModifierKey>{DVModifierKey.control});
    });

    test('a modifier with no key is refused', () {
      // 'Ctrl+' registers nothing a user could press.
      expect(() => DVAccelerator.parse('Ctrl+'), throwsA(isA<FormatException>()));
      expect(() => DVAccelerator.parse('Ctrl+Shift'), throwsA(isA<FormatException>()));
    });

    test('two keys are refused', () {
      expect(() => DVAccelerator.parse('K+J'), throwsA(isA<FormatException>()));
    });

    test('empty is refused', () {
      expect(() => DVAccelerator.parse(''), throwsA(isA<FormatException>()));
      expect(() => DVAccelerator.parse('+'), throwsA(isA<FormatException>()));
    });

    test('a repeated modifier is one modifier', () {
      expect(DVAccelerator.parse('Ctrl+Ctrl+K').modifiers, hasLength(1));
    });
  });

  group('what the platform receives', () {
    test('the canonical form is stable', () {
      // Two spellings of one shortcut must register as one, or a second
      // register() under a different spelling grabs the same key twice.
      expect(DVAccelerator.parse('shift+CTRL+k').canonical, 'Ctrl+Shift+K');
      expect(DVAccelerator.parse('Ctrl+Shift+K').canonical, 'Ctrl+Shift+K');
    });

    test('named keys keep their name', () {
      expect(DVAccelerator.parse('Ctrl+Space').key, 'space');
      expect(DVAccelerator.parse('Alt+F4').key, 'f4');
      expect(DVAccelerator.parse('Ctrl+ArrowUp').key, 'arrowup');
    });
  });
}
