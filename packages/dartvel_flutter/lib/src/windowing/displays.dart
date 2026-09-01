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

  /// Null only when the application knows of no displays at all.
  final DVDisplay? display;

  /// Whether [display] is the one the hint named.
  ///
  /// False means the window still opens, somewhere -- refusing to open is a
  /// worse answer than opening on the wrong screen -- but the caller must
  /// report [degradation] rather than let it pass silently.
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
  /// [profileNames] maps display id to the name a device profile gives it,
  /// which wins over whatever the panel calls itself.
  static List<DVDisplay> decode(
    Object? payload, {
    Map<String, String> profileNames = const <String, String>{},
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

    // Exactly one primary, always. Two would make DVDisplayHint.primary
    // ambiguous and its answer depend on iteration order; none would make it
    // unanswerable.
    int primary = entries.indexWhere((_Entry e) => e.isPrimary == true);
    if (primary < 0) primary = 0;

    return <DVDisplay>[
      for (int i = 0; i < entries.length; i++)
        entries[i].toDisplay(
          isPrimary: i == primary,
          profileName: profileNames[entries[i].id],
          ordinal: i,
        ),
    ];
  }

  /// Resolves [hint] against [displays].
  ///
  /// A hint that cannot be honoured falls back to the primary display and says
  /// so, rather than either throwing or relocating quietly. The quiet version
  /// is the one that matters: a customer-facing kiosk window appearing on the
  /// operator's screen because a panel was unplugged is a bug nobody sees
  /// until a customer does.
  static DVDisplayResolution resolve(
    List<DVDisplay> displays,
    DVDisplayHint? hint,
  ) {
    if (displays.isEmpty) {
      return const DVDisplayResolution(
        display: null,
        exact: false,
        degradation: DVWindowDegradation.displayUnavailable,
      );
    }

    final DVDisplay fallback =
        displays.firstWhere((DVDisplay d) => d.isPrimary, orElse: () => displays.first);

    if (hint == null) return _exact(fallback);

    switch (hint._kind) {
      case _DVDisplayHintKind.primary:
        return _exact(fallback);

      case _DVDisplayHintKind.secondary:
        for (final DVDisplay display in displays) {
          if (!display.isPrimary) return _exact(display);
        }
        return _degraded(fallback);

      case _DVDisplayHintKind.ordinal:
        final int index = hint._index ?? -1;
        if (index < 0 || index >= displays.length) return _degraded(fallback);
        return _exact(displays[index]);

      case _DVDisplayHintKind.id:
        for (final DVDisplay display in displays) {
          if (display.id == hint._value) return _exact(display);
        }
        return _degraded(fallback);

      case _DVDisplayHintKind.name:
        for (final DVDisplay display in displays) {
          if (display.name == hint._value) return _exact(display);
        }
        return _degraded(fallback);
    }
  }

  static DVDisplayResolution _exact(DVDisplay display) => DVDisplayResolution(
        display: display,
        exact: true,
        degradation: DVWindowDegradation.none,
      );

  static DVDisplayResolution _degraded(DVDisplay display) =>
      DVDisplayResolution(
        display: display,
        exact: false,
        degradation: DVWindowDegradation.displayUnavailable,
      );
}

/// One decoded payload entry, before primary selection.
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

    final double? left = _number(item['left']);
    final double? top = _number(item['top']);

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
