// What a kiosk's hardware-key block covers, and what it never covers.
//
// Kiosk blocks escape, never access. The combos that leave a kiosk -- the
// window switcher, the close key, the run dialog, the terminal -- are what a
// device-scope policy blocks; the keys accessibility needs are exempt from
// that block whatever the policy says, because the exemption is not the
// policy's to give up.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskPolicy policy({String scope = 'device', Map<String, Object?> input = const <String, Object?>{}}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': scope,
        'home': '/',
        'input': input,
        'exit': <String, Object?>{'method': 'pin', 'pin': 'secret:PIN'},
      },
    });

// Canonical spellings: modifiers Ctrl, Alt, Shift, Meta in that order, a
// single-letter key upper-cased, a named key as parsed.
Set<String> names(Iterable<DVAccelerator> combos) => <String>{for (final DVAccelerator a in combos) a.canonical};

void main() {
  test('a device-scope policy blocks the ways out', () {
    final Set<String> blocked = names(DVKioskEscapeKeys.toBlock(policy()));
    expect(blocked, containsAll(<String>['Alt+tab', 'Alt+f4', 'Alt+f2', 'Ctrl+escape', 'Ctrl+Alt+T', 'Meta+D']));
  });

  test('never the keys accessibility needs', () {
    for (final DVAccelerator combo in DVKioskEscapeKeys.combos) {
      expect(DVAccessibilityKeys.isExempt(DVKioskEscapeKeys.logical(combo)), isFalse,
          reason: '$combo is on the block list and exempt at once');
    }
    final Set<String> blocked = names(DVKioskEscapeKeys.toBlock(policy()));
    expect(blocked, isNot(contains('tab')));
    expect(blocked, isNot(contains('Shift+tab')));
    expect(blocked, isNot(contains('Alt+Meta+S')), reason: "the platform's accessibility shortcut");
  });

  test('a display-scope policy with passthrough blocks nothing', () {
    expect(DVKioskEscapeKeys.toBlock(policy(scope: 'display')), isEmpty);
  });

  test('a display-scope policy that asks for the block gets it, device-wide', () {
    // Keys are a device, not a display: the spec says a display-scope block
    // is either device-wide or nothing, and enforcement says which. This is
    // the device-wide half; DV-KIOSK-010 is reported by enforcement.
    expect(DVKioskEscapeKeys.toBlock(policy(scope: 'display', input: <String, Object?>{'hardwareKeys': 'block'})), isNotEmpty);
  });

  test('no policy, nothing blocked', () {
    expect(DVKioskEscapeKeys.toBlock(DVKioskPolicy.parse(null)), isEmpty);
  });

  test('a combo maps to the logical keys the exemption reads', () {
    expect(DVKioskEscapeKeys.logical(DVAccelerator.parse('Alt+Tab')),
        <LogicalKeyboardKey>{LogicalKeyboardKey.altLeft, LogicalKeyboardKey.tab});
    expect(DVKioskEscapeKeys.logical(DVAccelerator.parse('Super+Alt+S')),
        <LogicalKeyboardKey>{LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.keyS});
  });
}
