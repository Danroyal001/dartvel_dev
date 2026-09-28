/// Where a module's operation runs, and what it does there.
///
/// A module is called from three environments -- a native client, a browser
/// and the backend -- and for each one it declares exactly one of four
/// outcomes: `real`, `compat`, `noop` or `unavailable`. There is no default
/// and no fifth outcome. This file is the part of that a generated module
/// needs while it runs: which environment it is in, and the failure it
/// throws where it declared `unavailable`.
library;

/// The three places a module can be called from.
enum DVModuleEnvironment {
  /// A client built for Android, iOS, macOS, Windows, Linux or a TV.
  native,

  /// A client running in a browser.
  web,

  /// The application's server: a Dart VM with no Flutter engine.
  backend;

  /// The environment this code was compiled for.
  ///
  /// Decided at compile time, from the libraries the platform has: a browser
  /// build has `dart:js_interop`, a Flutter client has `dart:ui`, and the
  /// backend has neither.
  static DVModuleEnvironment get current {
    if (const bool.fromEnvironment('dart.library.js_interop')) return web;
    if (const bool.fromEnvironment('dart.library.ui')) return native;
    return backend;
  }
}

/// What a module's operation does in one environment.
enum DVModuleOutcome {
  /// The implementation ships and runs here.
  real,

  /// No direct carrier; a generated path reaches one that has it.
  compat,

  /// Deliberately does nothing here and returns a declared value.
  noop,

  /// Throws [DVModuleUnavailable], naming what was called and where.
  unavailable;

  /// The outcome a pubspec names, or null for anything else: a word that is
  /// not one of the four is refused rather than read as the nearest one.
  static DVModuleOutcome? parse(Object? word) {
    for (final DVModuleOutcome outcome in values) {
      if (outcome.name == word) return outcome;
    }
    return null;
  }
}

/// Thrown by an operation a module declares `unavailable` where it was
/// called.
///
/// The build refuses a call it can see reaching one (`DV-MODULE-013`); this
/// is what a call the build could not see does instead of returning a
/// plausible zero.
class DVModuleUnavailable implements Exception {
  const DVModuleUnavailable(this.module, this.operation, this.environment);

  /// The module id: what the application calls `DV.Modules.<id>`.
  final String module;

  /// The operation that was called.
  final String operation;

  /// Where it was called from.
  final DVModuleEnvironment environment;

  /// The diagnostic this failure carries.
  String get code => 'DV-MODULE-013';

  @override
  String toString() => '$code: $module.$operation is unavailable on '
      '${environment.name}. The module declares it so; call it from an '
      'environment where it is real, or check before calling.';
}
