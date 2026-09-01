/// Display enumeration behind `DV.Window.displays`, and hint resolution.
///
/// The contract lets a window ask for a display by hint rather than by
/// coordinates -- "the only placement input is `DVDisplayHint`, which display,
/// never where on it". Nothing enumerated displays, so every hint had nothing
/// to resolve against.
///
/// Two sources fill the list. A `window.displays` native binding reports what
/// the OS knows: layout origins, panel names, which display is primary.
/// Without that binding, Flutter's own `PlatformDispatcher.displays` still
/// gives size, pixel ratio and refresh rate for every display -- it is stable
/// and unflagged, unlike the desktop windowing API. What it does not give is
/// where the displays sit relative to each other, and that absence is reported
/// rather than filled in.
library dartvel.windowing.displays;

import 'dart:ui' show Rect, Size;

import 'window.dart' show DVWindowDegradation;

/// A display the application can address.
final class DVDisplay {
  const DVDisplay({
    required this.id,
    required this.name,
    required this.bounds,
    required this.devicePixelRatio,
    required this.refreshRate,
    required this.isPrimary,
    required this.hasLayout,
  });

  /// Stable for the display's connection.
  final String id;

  /// From the device profile when one names it, else the OS-reported panel
  /// name, else derived. Never empty: it reaches logs and `dartvel explain`.
  final String name;

  /// Logical pixels, so a layout decision reads the same number it lays out
  /// in.
  ///
  /// The size is always real. The origin is meaningful only when [hasLayout],
  /// and is zero otherwise.
  final Rect bounds;

  final double devicePixelRatio;
  final double refreshRate;
  final bool isPrimary;

  /// Whether [bounds] carries a real layout origin.
  ///
  /// False when the display list came from Flutter alone, which reports no
  /// origin. Placement never depends on this -- a window asks for a display,
  /// not a rectangle -- but a caller reasoning about arrangement needs to know
  /// the difference between "at the origin" and "position unknown".
  final bool hasLayout;

  @override
  String toString() => 'DVDisplay($id, $name, ${bounds.width}x${bounds.height}'
      '@${devicePixelRatio}x${isPrimary ? ', primary' : ''})';
}

/// Which display a window is asking for.
final class DVDisplayHint {
  const DVDisplayHint._(this._kind, {int? index, String? value})
      : _index = index,
        _value = value;

  final _DVDisplayHintKind _kind;
  final int? _index;
  final String? _value;

  /// The primary display.
  static const DVDisplayHint primary =
      DVDisplayHint._(_DVDisplayHintKind.primary);

  /// The first non-primary display, in the order the OS reports them.
  static const DVDisplayHint secondary =
      DVDisplayHint._(_DVDisplayHintKind.secondary);

  /// The display at [index] in OS order.
  static DVDisplayHint byIndex(int index) =>
      DVDisplayHint._(_DVDisplayHintKind.ordinal, index: index);

  /// The display with [id].
  static DVDisplayHint byId(String id) =>
      DVDisplayHint._(_DVDisplayHintKind.id, value: id);

  /// The display named [name], usually from a device profile.
  static DVDisplayHint byName(String name) =>
      DVDisplayHint._(_DVDisplayHintKind.name, value: name);

  @override
  String toString() => switch (_kind) {
        _DVDisplayHintKind.primary => 'DVDisplayHint.primary',
        _DVDisplayHintKind.secondary => 'DVDisplayHint.secondary',
        _DVDisplayHintKind.ordinal => 'DVDisplayHint.byIndex($_index)',
        _DVDisplayHintKind.id => 'DVDisplayHint.byId($_value)',
        _DVDisplayHintKind.name => 'DVDisplayHint.byName($_value)',
      };
}

enum _DVDisplayHintKind { primary, secondary, ordinal, id, name }

/// What a hint resolved to, and whether it was what was asked for.
final class DVDisplayResolution {
  const DVDisplayResolution({
    required this.display,
    required this.exact,
    required this.degradation,
  });

  /// The display the hint named, or null when nothing matched it.
  ///
  /// Null is never a substitute display. It means the caller should do what it
  /// would have done with no hint at all -- for a window, let the OS place it.
  final DVDisplay? display;

  /// Whether the hint was honoured.
  ///
  /// False means a hint was given and nothing matched it. The window still
  /// opens -- refusing to open is a worse answer -- but on no particular
  /// display, and the caller must report [degradation] rather than let it pass
  /// silently.
  final bool exact;

  final DVWindowDegradation degradation;
}

/// Reads display lists and resolves hints against them.
final class DVDisplays {
  const DVDisplays._();

  /// Turns a native or Flutter-sourced payload into displays.
  ///
  /// Never throws: the payload comes across a native binding, so it is not
  /// trusted input, and an application that cannot enumerate displays should
  /// fall back to a single-display world rather than fail to start.
  ///
  /// [profile] is a device profile's `displays:` map -- a name against the
  /// position it names, as `displays: { Customer: { index: 1 } }`. A profile
  /// names displays by position rather than by id because that is what its
  /// author knows about a machine they have not booted yet, and the name wins
  /// over whatever the panel's EDID calls itself.
  ///
  /// An entry pointing past the end names nothing. A two-display profile
  /// booted with one screen attached must not name the operator's display
  /// "Customer", which would send customer-facing output there under a name
  /// saying it was safe.
  static List<DVDisplay> decode(
    Object? payload, {
    Map<String, int> profile = const <String, int>{},
  }) {
    if (payload is! List) return const <DVDisplay>[];

    final List<_Entry> entries = <_Entry>[];
    for (final Object? item in payload) {
      final _Entry? entry = _Entry.read(item);
      // A malformed or sizeless entry is dropped rather than defaulted: a 0x0
      // display would satisfy every hint and place a window nowhere.
      if (entry != null) entries.add(entry);
    }
    if (entries.isEmpty) return const <DVDisplay>[];

    // At most one primary, and never an invented one. Two would make
    // DVDisplayHint.primary depend on iteration order, so the first reported
    // wins; none stays none, because a platform that designates no primary --
    // Xinerama reports none at all, and some X servers set none -- has not
    // said which screen the operator is looking at, and picking the first is a
    // guess that DVDisplayHint.secondary would then build on.
    final int primary = entries.indexWhere((_Entry e) => e.isPrimary == true);

    // Position to name. Two names on one position would otherwise resolve by
    // map iteration order; the first written wins, and does so predictably.
    final Map<int, String> named = <int, String>{};
    for (final MapEntry<String, int> entry in profile.entries) {
      named.putIfAbsent(entry.value, () => entry.key);
    }

    return <DVDisplay>[
      for (int i = 0; i < entries.length; i++)
        entries[i].toDisplay(
          isPrimary: i == primary,
          profileName: named[i],
          ordinal: i,
        ),
    ];
  }

  /// Resolves [hint] against [displays].
  ///
  /// **Never falls back to another display.** A hint naming a projector that
  /// is unplugged must not resolve to the primary display: the output would
  /// appear on the operator's own screen, in front of the room, and it would
  /// look like it had worked. A miss returns a null display and
  /// [DVWindowDegradation.displayUnavailable], and the caller decides -- which
  /// for `open()` means letting the OS place the window, exactly as if no hint
  /// had been given, while still reporting the miss.
  static DVDisplayResolution resolve(
    List<DVDisplay> displays,
    DVDisplayHint? hint,
  ) {
    // Nothing was asked for, so nothing was missed.
    if (hint == null) {
      return const DVDisplayResolution(
        display: null,
        exact: true,
        degradation: DVWindowDegradation.none,
      );
    }

    final DVDisplay? found = _match(displays, hint);
    if (found == null) {
      return const DVDisplayResolution(
        display: null,
        exact: false,
        degradation: DVWindowDegradation.displayUnavailable,
      );
    }
    return DVDisplayResolution(
      display: found,
      exact: true,
      degradation: DVWindowDegradation.none,
    );
  }

  static DVDisplay? _match(List<DVDisplay> displays, DVDisplayHint hint) {
    if (displays.isEmpty) return null;
    switch (hint._kind) {
      case _DVDisplayHintKind.primary:
        return _firstWhere(displays, (DVDisplay d) => d.isPrimary);

      case _DVDisplayHintKind.secondary:
        // "The first non-primary display" only means anything once something
        // is primary. Where the platform designates none, every display is
        // nominally non-primary and answering would hand back whichever the
        // enumeration happened to list first -- the operator's own screen as
        // readily as the projector.
        if (!displays.any((DVDisplay d) => d.isPrimary)) return null;
        return _firstWhere(displays, (DVDisplay d) => !d.isPrimary);

      case _DVDisplayHintKind.ordinal:
        final int index = hint._index ?? -1;
        return index >= 0 && index < displays.length ? displays[index] : null;

      case _DVDisplayHintKind.id:
        return _firstWhere(displays, (DVDisplay d) => d.id == hint._value);

      case _DVDisplayHintKind.name:
        return _firstWhere(displays, (DVDisplay d) => d.name == hint._value);
    }
  }

  static DVDisplay? _firstWhere(
    List<DVDisplay> displays,
    bool Function(DVDisplay) test,
  ) {
    for (final DVDisplay display in displays) {
      if (test(display)) return display;
    }
    return null;
  }
}

/// One decoded payload entry, before the primary is picked out.
final class _Entry {
  const _Entry({
    required this.id,
    required this.physical,
    required this.devicePixelRatio,
    required this.refreshRate,
    required this.name,
    required this.isPrimary,
    required this.origin,
  });

  final String id;
  final Size physical;
  final double devicePixelRatio;
  final double refreshRate;
  final String? name;
  final bool? isPrimary;
  final ({double left, double top})? origin;

  /// Reads one entry, or null if it does not describe a usable display.
  static _Entry? read(Object? item) {
    if (item is! Map) return null;

    final double? width = _number(item['width']);
    final double? height = _number(item['height']);
    // Sizeless is not zero-sized: drop it.
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }

    // Both spellings: 'x'/'y' is what the X11 binding reports, 'left'/'top'
    // reads better in a hand-written payload. One decoder for both.
    final double? left = _number(item['left']) ?? _number(item['x']);
    final double? top = _number(item['top']) ?? _number(item['y']);

    final double ratio = _number(item['devicePixelRatio']) ?? 1.0;
    return _Entry(
      id: '${item['id'] ?? ''}'.isEmpty ? _fallbackId(item) : '${item['id']}',
      physical: Size(width, height),
      // A zero or negative ratio would divide the size to infinity.
      devicePixelRatio: ratio > 0 ? ratio : 1.0,
      refreshRate: _number(item['refreshRate']) ?? 0.0,
      name: item['name'] is String && (item['name'] as String).trim().isNotEmpty
          ? (item['name'] as String).trim()
          : null,
      isPrimary: item['isPrimary'] is bool ? item['isPrimary'] as bool : null,
      origin: left != null && top != null ? (left: left, top: top) : null,
    );
  }

  DVDisplay toDisplay({
    required bool isPrimary,
    required String? profileName,
    required int ordinal,
  }) {
    final ({double left, double top})? at = origin;
    return DVDisplay(
      id: id,
      // A device profile addresses displays by role; the OS name is whatever
      // the panel's EDID says.
      name: profileName ?? name ?? 'Display ${ordinal + 1}',
      bounds: Rect.fromLTWH(
        at?.left ?? 0,
        at?.top ?? 0,
        physical.width / devicePixelRatio,
        physical.height / devicePixelRatio,
      ),
      devicePixelRatio: devicePixelRatio,
      refreshRate: refreshRate,
      isPrimary: isPrimary,
      hasLayout: at != null,
    );
  }

  static String _fallbackId(Map<Object?, Object?> item) =>
      'display-${item.hashCode}';

  static double? _number(Object? value) => switch (value) {
        final num n when n.isFinite => n.toDouble(),
        _ => null,
      };
}
