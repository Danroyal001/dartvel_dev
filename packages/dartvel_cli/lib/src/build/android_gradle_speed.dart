/// Gradle's own speed settings in the Android project the build generates.
///
/// `flutter create` writes a `gradle.properties` with none of them, and
/// Gradle's defaults are a serial build that recomputes every task output.
/// Two settings change how fast a build is and never what it builds:
///
/// - `org.gradle.caching=true`: a task whose inputs hash the same as an
///   earlier run's takes that run's outputs from `~/.gradle/caches`, which
///   outlives the `android/` folder (the native folders are regenerated, the
///   machine's Gradle cache is not). AGP's compile, dex and R8 tasks are
///   cacheable; an output is reused only when every input is byte-identical.
/// - `org.gradle.parallel=true`: independent projects (the app and each
///   plugin's module) build at once instead of one after another.
///
/// The configuration cache is left to the project: a Flutter build spends
/// its time compiling, not configuring, and the cache stores a resolved task
/// graph that Flutter's plugin would have to be proven safe with first.
///
/// A setting the project already names is the project's decision and is
/// left as it is, whatever its value.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The settings written, in the order they are appended.
const Map<String, String> dvAndroidGradleSpeedSettings = <String, String>{
  'org.gradle.caching': 'true',
  'org.gradle.parallel': 'true',
};

/// Adds [dvAndroidGradleSpeedSettings] the project does not already name to
/// `android/gradle.properties` under [root]. Returns whether the file
/// changed; false with no `android/` folder, which is never created here.
bool dvWriteAndroidGradleSpeed(String root) {
  final Directory android = Directory(p.join(root, 'android'));
  if (!android.existsSync()) return false;
  final File file = File(p.join(android.path, 'gradle.properties'));
  final String before = file.existsSync() ? file.readAsStringSync() : '';
  final Set<String> named = <String>{
    for (final String line in before.split('\n'))
      if (_key(line) case final String key) key,
  };
  final List<String> missing = <String>[
    for (final MapEntry<String, String> setting
        in dvAndroidGradleSpeedSettings.entries)
      if (!named.contains(setting.key)) '${setting.key}=${setting.value}',
  ];
  if (missing.isEmpty) return false;
  final StringBuffer after = StringBuffer(before);
  if (before.isNotEmpty && !before.endsWith('\n')) after.writeln();
  after.writeln('# Written by dartvel build: Gradle reuses unchanged task '
      'outputs and builds modules in parallel.');
  missing.forEach(after.writeln);
  file.writeAsStringSync(after.toString());
  return true;
}

/// The property a `gradle.properties` line sets, or null for a comment or a
/// blank line. Keys end at `=`, `:` or whitespace, as Java properties do.
String? _key(String line) {
  final String trimmed = line.trimLeft();
  if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!')) {
    return null;
  }
  final RegExpMatch? match = RegExp(r'^([^=:\s]+)').firstMatch(trimmed);
  return match?.group(1);
}
