/// Remembering a window's size between runs.
///
/// `window.persistState` and `window.restoreState` were on the list of names to
/// bind natively on every platform. They do not need binding: persisting a
/// window's state means recording its size and putting it back, and both halves
/// already exist. Flutter knows its own window size, and `window.setSize` is
/// bound where a window can be resized at all.
///
/// Composing them rather than binding them has a second benefit. On macOS,
/// where `window.setSize` is deliberately unbound because it needs the main
/// thread, this still remembers the size and simply declines to apply it —
/// rather than throwing at an application that asked to be tidy.
library dartvel_flutter.windowing.window_state;

import 'dart:convert';

/// A window size worth restoring.
class DVWindowState {
  final int width;
  final int height;

  const DVWindowState({required this.width, required this.height});

  String encode() => jsonEncode(<String, Object?>{
        'width': width,
        'height': height,
      });

  /// Reads a stored state, or null when it cannot be trusted.
  ///
  /// Null rather than an exception for every failure. The value comes from
  /// storage written by some earlier version of the application, so it is not
  /// trustworthy input, and a throw here would break startup over a stale
  /// preference.
  static DVWindowState? decode(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(stored);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;

    final width = decoded['width'];
    final height = decoded['height'];
    if (width is! int || height is! int) return null;

    // Zero and negative sizes are what a crashed or minimised window leaves
    // behind, and restoring one produces a window nobody can find.
    if (width <= 0 || height <= 0) return null;

    return DVWindowState(width: width, height: height);
  }

  @override
  bool operator ==(Object other) =>
      other is DVWindowState && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'DVWindowState(${width}x$height)';
}

/// The storage key for a named window.
///
/// Namespaced, because this shares a store with whatever the application keeps
/// there and a bare "main" is exactly the key someone else will also choose.
String dvWindowStateKey(String name) => 'dartvel.window.$name';
