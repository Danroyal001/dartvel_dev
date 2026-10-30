/// Whether this host can run a module's binding kind.
///
/// A generated module's tests ask this before calling into a carrier and
/// pass the answer as the test's skip reason: a binding kind that cannot run
/// on the host is skipped by target rather than failed, and the skip says
/// why -- a silently skipped test is a test that passes for the wrong reason.
library;

import 'dart:io';

/// Why this host cannot run a [kind] binding, or null when it can.
///
/// [which], [environment] and [os] are the host as the carriers read it:
/// the executable on PATH, the process environment, the operating system.
/// A test passes its own.
String? dvModuleHostRefusal(
  String kind, {
  String? Function(String executable)? which,
  Map<String, String>? environment,
  String? os,
}) {
  final String? Function(String) find = which ?? _onPath;
  final Map<String, String> env = environment ?? Platform.environment;
  final String system = os ?? Platform.operatingSystem;
  switch (kind) {
    case 'npm':
    case 'wasm':
      // The carrier's own order: DARTVEL_NODE, then the copy bundled beside
      // an application (which a test run has none of), then PATH.
      final String? named = env['DARTVEL_NODE'];
      if (named != null && named.isNotEmpty) return null;
      if (find('node') != null) return null;
      return '$kind modules run in Node on the backend, and Node is not on '
          'this host: put node on PATH or name it in DARTVEL_NODE.';
    case 'apple':
      if (system == 'macos' || find('swiftc') != null) return null;
      return 'apple modules are built with swiftc off a Mac, and swiftc is '
          'not on this host.';
    case 'jvm':
      return 'jvm modules are reached over JNI on Android, and the Dart VM '
          'running this suite has no JVM attached.';
    default:
      return null;
  }
}

String? _onPath(String executable) {
  final String separator = Platform.isWindows ? ';' : ':';
  final List<String> names = Platform.isWindows
      ? <String>['$executable.exe', '$executable.cmd', executable]
      : <String>[executable];
  for (final String dir in (Platform.environment['PATH'] ?? '').split(separator)) {
    if (dir.isEmpty) continue;
    for (final String name in names) {
      final String candidate = '$dir${Platform.pathSeparator}$name';
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return null;
}
