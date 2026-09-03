import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvLiveWindowsPathFor;

/// What a running instance of the project at [root] has published beside its
/// single-instance lock: its open windows and its performance measurements.
///
/// The app writes the file on every change with the time it wrote; a file
/// older than [liveFor] is a stopped app, not a live one, and is reported as
/// such rather than as its last state. Shared by `dartvel inspect windows`
/// and `dartvel analyze performance` so the two cannot disagree about
/// whether the app is running.
class DVLiveWindowsFile {
  const DVLiveWindowsFile._(this.live, this.age);

  static const Duration liveFor = Duration(seconds: 30);

  /// The decoded file when it is fresh, else null.
  final Map<String, Object?>? live;

  /// How old the file is, when there is one at all.
  final Duration? age;

  static DVLiveWindowsFile read(String root) {
    final File file = File(dvLiveWindowsPathFor(appName(root)));
    if (!file.existsSync()) return const DVLiveWindowsFile._(null, null);
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const DVLiveWindowsFile._(null, null);
      final DateTime? at = DateTime.tryParse('${decoded['at']}');
      if (at == null) return const DVLiveWindowsFile._(null, null);
      final Duration age = DateTime.now().toUtc().difference(at.toUtc());
      if (age > liveFor) return DVLiveWindowsFile._(null, age);
      return DVLiveWindowsFile._(decoded.cast<String, Object?>(), age);
    } on FormatException {
      return const DVLiveWindowsFile._(null, null);
    }
  }

  /// One line saying the app is not running, and when it last was.
  String get notRunning => age == null
      ? 'not running (no instance has published its windows)'
      : 'not running (last seen ${age!.inMinutes}m ago)';

  static String appName(String root) {
    final File pubspec = File('$root/pubspec.yaml');
    if (!pubspec.existsSync()) return 'dartvel';
    final RegExpMatch? m = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true)
        .firstMatch(pubspec.readAsStringSync());
    return m?.group(1) ?? 'dartvel';
  }
}
