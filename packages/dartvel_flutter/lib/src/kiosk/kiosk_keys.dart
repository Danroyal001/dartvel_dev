// What a kiosk's hardware-key block covers, and what it never covers.
//
// Kiosk blocks escape, never access. These are the combos that leave a
// kiosk on a desktop -- the window switcher, the close key, the run dialog,
// the terminal, the desktop shortcuts -- filtered through the accessibility
// exemption, which is not the policy's to give up.
import 'package:dartvel_core/dartvel.dart' show DVKioskPolicy, DVKioskScope;
import 'package:flutter/services.dart';

import '../accessibility/switch_control.dart';
import '../platform/accelerator.dart';

class DVKioskEscapeKeys {
  DVKioskEscapeKeys._();

  /// Every combo a device-scope block covers, before the exemption.
  static final List<DVAccelerator> combos = <DVAccelerator>[
    for (final String text in <String>[
      'Alt+Tab',
      'Alt+Shift+Tab',
      'Alt+F4',
      'Alt+F2',
      'Alt+Escape',
      'Alt+Space',
      'Ctrl+Escape',
      'Ctrl+Alt+T',
      'Ctrl+Alt+D',
      'Ctrl+Alt+Delete',
      'Ctrl+Alt+L',
      'Super+D',
      'Super+A',
      'Super+Tab',
      'Super+L',
      'Super+E',
      'Super+R',
    ])
      DVAccelerator.parse(text),
  ];

  static final Map<DVModifierKey, LogicalKeyboardKey> _modifiers =
      <DVModifierKey, LogicalKeyboardKey>{
    DVModifierKey.control: LogicalKeyboardKey.controlLeft,
    DVModifierKey.shift: LogicalKeyboardKey.shiftLeft,
    DVModifierKey.alt: LogicalKeyboardKey.altLeft,
    DVModifierKey.meta: LogicalKeyboardKey.metaLeft,
  };

  static final Map<String, LogicalKeyboardKey> _keys = <String, LogicalKeyboardKey>{
    'tab': LogicalKeyboardKey.tab,
    'space': LogicalKeyboardKey.space,
    'enter': LogicalKeyboardKey.enter,
    'return': LogicalKeyboardKey.enter,
    'escape': LogicalKeyboardKey.escape,
    'esc': LogicalKeyboardKey.escape,
    'delete': LogicalKeyboardKey.delete,
    'del': LogicalKeyboardKey.delete,
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,
  };

  /// The keys down together for [combo], as the exemption reads them.
  static Set<LogicalKeyboardKey> logical(DVAccelerator combo) {
    final Set<LogicalKeyboardKey> out = <LogicalKeyboardKey>{
      for (final DVModifierKey m in combo.modifiers) _modifiers[m]!,
    };
    final String key = combo.key.toLowerCase();
    final LogicalKeyboardKey? named = _keys[key];
    if (named != null) {
      out.add(named);
    } else if (key.length == 1) {
      final LogicalKeyboardKey? found = LogicalKeyboardKey.findKeyByKeyId(
          LogicalKeyboardKey.keyA.keyId + (key.codeUnitAt(0) - 'a'.codeUnitAt(0)));
      out.add(found ?? LogicalKeyboardKey(key.codeUnitAt(0)));
    } else if (RegExp(r'^f\d{1,2}$').hasMatch(key)) {
      final int n = int.parse(key.substring(1));
      out.add(LogicalKeyboardKey.findKeyByKeyId(LogicalKeyboardKey.f1.keyId + n - 1)!);
    } else {
      out.add(LogicalKeyboardKey(key.hashCode));
    }
    return out;
  }

  /// What [policy] blocks: the combos, less the exempt, when the policy
  /// blocks hardware keys or shortcuts -- device scope by default, display
  /// scope only when asked, and then device-wide because keys are a device.
  static List<DVAccelerator> toBlock(DVKioskPolicy policy) {
    if (!policy.enabled) return const <DVAccelerator>[];
    if (!policy.blockHardwareKeys && !policy.blockShortcuts) {
      return const <DVAccelerator>[];
    }
    if (policy.scope == DVKioskScope.display && !policy.blockHardwareKeys) {
      return const <DVAccelerator>[];
    }
    return <DVAccelerator>[
      for (final DVAccelerator c in combos)
        if (!DVAccessibilityKeys.isExempt(logical(c))) c,
    ];
  }
}
