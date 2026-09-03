/// Reading an accelerator string, before any platform sees it.
///
/// A global shortcut arrives as text -- `Ctrl+K`, `CmdOrCtrl+Shift+P` -- and
/// every native binding has to turn it into the same modifiers and the same
/// key. Parsed once here rather than once per platform, or the Linux and
/// Windows bindings drift on what `Cmd` means and a shortcut works on one and
/// not the other with no error anywhere.
library dartvel.platform.accelerator;

/// A modifier, in platform-neutral terms.
enum DVModifierKey { control, shift, alt, meta }

/// A parsed accelerator.
class DVAccelerator {
  const DVAccelerator({required this.modifiers, required this.key});

  final Set<DVModifierKey> modifiers;

  /// Lower-case. A letter, a digit, or a named key such as `f5`, `space`,
  /// `arrowup`.
  final String key;

  static const Map<String, DVModifierKey> _names = <String, DVModifierKey>{
    'ctrl': DVModifierKey.control,
    'control': DVModifierKey.control,
    'shift': DVModifierKey.shift,
    'alt': DVModifierKey.alt,
    'option': DVModifierKey.alt,
    'meta': DVModifierKey.meta,
    'cmd': DVModifierKey.meta,
    'command': DVModifierKey.meta,
    'super': DVModifierKey.meta,
    'win': DVModifierKey.meta,
  };

  /// Reads [text].
  ///
  /// `CmdOrCtrl` is the one token allowed to mean different things on
  /// different machines, and it says so in its name: [primaryIsMeta] decides,
  /// and a binding passes what its platform is.
  ///
  /// Throws [FormatException] for a modifier with no key -- `Ctrl+` registers
  /// nothing a user could press -- for two keys, and for nothing at all.
  static DVAccelerator parse(String text, {bool primaryIsMeta = false}) {
    final List<String> parts = text
        .split('+')
        .map((String p) => p.trim().toLowerCase())
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      throw FormatException('An accelerator needs a key.', text);
    }

    final Set<DVModifierKey> modifiers = <DVModifierKey>{};
    String? key;
    for (final String part in parts) {
      if (part == 'cmdorctrl' || part == 'commandorcontrol') {
        modifiers.add(primaryIsMeta ? DVModifierKey.meta : DVModifierKey.control);
        continue;
      }
      final DVModifierKey? modifier = _names[part];
      if (modifier != null) {
        modifiers.add(modifier);
        continue;
      }
      if (key != null) {
        throw FormatException(
            'An accelerator has one key; "$text" names two ($key and $part).',
            text);
      }
      key = part;
    }
    if (key == null) {
      throw FormatException(
          'An accelerator needs a key; "$text" is only modifiers.', text);
    }
    return DVAccelerator(modifiers: modifiers, key: key);
  }

  /// One spelling for one shortcut, so two register() calls under different
  /// spellings cannot grab the same key twice.
  String get canonical {
    const List<(DVModifierKey, String)> order = <(DVModifierKey, String)>[
      (DVModifierKey.control, 'Ctrl'),
      (DVModifierKey.alt, 'Alt'),
      (DVModifierKey.shift, 'Shift'),
      (DVModifierKey.meta, 'Meta'),
    ];
    final List<String> parts = <String>[
      for (final (DVModifierKey m, String name) in order)
        if (modifiers.contains(m)) name,
      key.length == 1 ? key.toUpperCase() : key,
    ];
    return parts.join('+');
  }

  @override
  String toString() => 'DVAccelerator($canonical)';
}
