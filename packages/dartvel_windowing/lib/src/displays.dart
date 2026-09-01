part of '../dartvel_windowing.dart';

/// A display the window system reports.
///
/// Field for field what the Multi-Window section fixes, minus `kioskOwner`,
/// which belongs to the kiosk implementation rather than to enumeration.
@immutable
class DVDisplay {
  const DVDisplay({
    required this.id,
    required this.name,
    required this.bounds,
    required this.devicePixelRatio,
    required this.isPrimary,
  });

  /// Stable for the display's connection.
  final String id;

  /// From the device profile where one names it, else OS-reported.
  final String name;

  /// Logical pixels, in the desktop's coordinate space.
  final Rect bounds;

  final double devicePixelRatio;

  final bool isPrimary;

  @override
  String toString() => 'DVDisplay($id, $name, $bounds, '
      'dpr=$devicePixelRatio, primary=$isPrimary)';
}

/// Reads the displays the `window.displays` binding reports.
class DVDisplays {
  const DVDisplays._();

  /// The binding name the specification fixes for desktop.
  static const String binding = 'window.displays';

  /// Converts what the binding returned into displays.
  ///
  /// A row without usable bounds is **dropped rather than defaulted**. A
  /// display reported at 0x0 would still be offered as a projector target and
  /// would then show nothing, which is worse than not offering it: the failure
  /// moves from "no second display" at setup time to a black screen in front
  /// of a congregation.
  static List<DVDisplay> fromBinding(Object? reported) {
    if (reported is! List) return const <DVDisplay>[];
    final displays = <DVDisplay>[];
    for (final row in reported) {
      if (row is! Map) continue;
      final width = _asDouble(row['width']);
      final height = _asDouble(row['height']);
      if (width == null || height == null || width <= 0 || height <= 0) {
        continue;
      }
      displays.add(DVDisplay(
        id: '${row['id'] ?? 'display-${displays.length}'}',
        name: '${row['name'] ?? row['id'] ?? 'display-${displays.length}'}',
        bounds: Rect.fromLTWH(
          _asDouble(row['x']) ?? 0,
          _asDouble(row['y']) ?? 0,
          width,
          height,
        ),
        devicePixelRatio: _asDouble(row['devicePixelRatio']) ?? 1.0,
        isPrimary: row['isPrimary'] == true,
      ));
    }
    return List<DVDisplay>.unmodifiable(displays);
  }

  /// Asks the platform which displays exist.
  ///
  /// Returns empty where there is no window system to ask — a headless
  /// container, a CI runner without an X server — rather than throwing. "No
  /// displays" is a true answer there, and an application that wanted a
  /// projector finds out by getting nothing back from
  /// [DVDisplayHint.secondary], which is the same path as an unplugged cable.
  static Future<List<DVDisplay>> query() async {
    try {
      return fromBinding(await DVNativeBridge.invoke<Object?>(binding, null));
    } catch (_) {
      return const <DVDisplay>[];
    }
  }

  static double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : null;
}

/// Which display a window should go to.
///
/// Placement is not part of the contract: there is no position and no
/// `setPosition`, because Wayland forbids app-positioned windows and Flutter's
/// windowing API exposes none. A hint names *which display*, never where on it.
@immutable
class DVDisplayHint {
  const DVDisplayHint._(this._kind, {this.index, this.value});

  /// The display the OS calls primary.
  static const DVDisplayHint primary = DVDisplayHint._(_DVDisplayHintKind.primary);

  /// The first non-primary display, in OS order. The projector, usually.
  static const DVDisplayHint secondary =
      DVDisplayHint._(_DVDisplayHintKind.secondary);

  /// The display at [index] in OS order.
  const DVDisplayHint.byIndex(int index)
      : this._(_DVDisplayHintKind.atIndex, index: index);

  /// The display with this stable id.
  const DVDisplayHint.byId(String id)
      : this._(_DVDisplayHintKind.withId, value: id);

  /// The display with this name. Device profiles name displays.
  const DVDisplayHint.byName(String name)
      : this._(_DVDisplayHintKind.withName, value: name);

  final _DVDisplayHintKind _kind;
  final int? index;
  final String? value;

  /// The display this hint names, or null when nothing matches.
  ///
  /// **Never falls back to another display.** A hint for a projector that is
  /// unplugged resolving to the primary would put the output on the operator's
  /// own screen, in front of the room. The caller decides what to do instead —
  /// the kiosk contract's answer is a fullscreen page and `DV-WINDOW-010`.
  DVDisplay? resolve(List<DVDisplay> displays) {
    if (displays.isEmpty) return null;
    switch (_kind) {
      case _DVDisplayHintKind.primary:
        return _firstOrNull(displays.where((d) => d.isPrimary));
      case _DVDisplayHintKind.secondary:
        // "First non-primary" is only meaningful once something is primary.
        // Where the platform designates none -- Xinerama reports no primary at
        // all, and some X servers set none -- every display is nominally
        // non-primary, and answering would hand back the operator's own screen.
        if (!displays.any((d) => d.isPrimary)) return null;
        return _firstOrNull(displays.where((d) => !d.isPrimary));
      case _DVDisplayHintKind.atIndex:
        final i = index!;
        return i >= 0 && i < displays.length ? displays[i] : null;
      case _DVDisplayHintKind.withId:
        return _firstOrNull(displays.where((d) => d.id == value));
      case _DVDisplayHintKind.withName:
        return _firstOrNull(displays.where((d) => d.name == value));
    }
  }

  static DVDisplay? _firstOrNull(Iterable<DVDisplay> it) =>
      it.isEmpty ? null : it.first;
}

enum _DVDisplayHintKind { primary, secondary, atIndex, withId, withName }
