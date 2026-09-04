/// The id Chrome derived for an unpacked extension, read from the profile it
/// just wrote.
///
///     dart tool/ci/chrome_extension_id.dart <extension-dir> [profile]
///
/// Prints the id on stdout and nothing else, so a step can capture it; the
/// dump of everything Chrome recorded goes to stderr, because the first
/// attempt at this matched on an exact path string, found nothing, and could
/// not say whether Chrome had rejected the manifest or the lookup was simply
/// wrong.
///
/// Exits zero either way. An extension Chrome declined to install is the
/// caller's decision to act on, and it already checks for an empty id.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('usage: chrome_extension_id.dart <dir> [profile]');
    return 2;
  }
  final String wanted =
      Directory(arguments.first).absolute.resolveSymbolicLinksSync();
  final String profile =
      arguments.length > 1 ? arguments[1] : '/tmp/chrome-profile';
  final File preferences = File('$profile/Default/Preferences');
  if (!preferences.existsSync()) {
    stderr.writeln('NO PREFERENCES FILE');
    return 0;
  }

  final Object? decoded = jsonDecode(preferences.readAsStringSync());
  final Object? extensions =
      decoded is Map<String, Object?> ? decoded['extensions'] : null;
  final Object? raw =
      extensions is Map ? extensions['settings'] : null;
  final Map<String, Object?> settings =
      raw is Map<String, Object?> ? raw : const <String, Object?>{};

  // Everything Chrome recorded, to the log.
  settings.forEach((String key, Object? value) {
    final Map<Object?, Object?> entry =
        value is Map ? value : const <Object?, Object?>{};
    stderr.writeln('  $key location=${entry['location']} path=${entry['path']}');
  });

  for (final MapEntry<String, Object?> entry in settings.entries) {
    final Map<Object?, Object?> value =
        entry.value is Map ? entry.value! as Map<Object?, Object?> : const <Object?, Object?>{};
    final Object? recorded = value['path'];
    if (recorded == null || '$recorded'.isEmpty) continue;
    // Chrome may store the path normalised or relative to the profile, so
    // compare resolved paths.
    final Directory directory = Directory('$recorded');
    if (!directory.existsSync()) continue;
    if (directory.absolute.resolveSymbolicLinksSync() == wanted) {
      stdout.writeln(entry.key);
      return 0;
    }
  }

  // Location 4 is UNPACKED. Falling back to the only one of those is what
  // makes this work when Chrome stored a path this cannot resolve.
  final List<String> unpacked = <String>[
    for (final MapEntry<String, Object?> entry in settings.entries)
      if (entry.value is Map && (entry.value! as Map)['location'] == 4)
        entry.key,
  ];
  if (unpacked.length == 1) stdout.writeln(unpacked.single);
  return 0;
}
