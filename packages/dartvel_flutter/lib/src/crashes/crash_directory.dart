/// Where crash records are kept between the run that had them and the run
/// that sends them, and the install id that groups one device's reports.
library;

import 'package:dartvel_core/dartvel.dart' show dvAnalyticsRandomId;

/// The directory crash records for [appId] go in on [os], or null when the
/// platform gives no directory that survives a restart.
///
/// `DARTVEL_CRASH_DIR` wins everywhere, for a deployment that mounts one. The
/// rest is the per-user data directory each platform keeps across reboots —
/// never the temp directory, which is wiped exactly when a crash loop ends
/// in a restart. Null rather than a guess: a relative path is written from
/// whatever the working directory is, which on a device is `/`.
///
/// [androidStateDirectory] is the device runtime's directory inside the
/// application's files directory; Android sets no HOME, and the files
/// directory is the only place an application may write.
String? dvCrashDirectoryFor({
  required String appId,
  required String os,
  required Map<String, String> environment,
  String? androidStateDirectory,
}) {
  String? usable(String? value) {
    if (value == null) return null;
    String trimmed = value.trim();
    while (trimmed.length > 1 &&
        (trimmed.endsWith('/') || trimmed.endsWith(r'\'))) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.isEmpty || trimmed == '/' || trimmed == r'\') return null;
    return trimmed;
  }

  final String? declared = usable(environment['DARTVEL_CRASH_DIR']);
  if (declared != null) return declared;

  switch (os) {
    case 'android':
      final String? state = usable(androidStateDirectory);
      if (state == null) return null;
      final int slash = state.lastIndexOf('/');
      final String? files =
          slash <= 0 ? null : usable(state.substring(0, slash));
      return files == null ? null : '$files/dartvel-crashes';
    case 'ios':
    case 'macos':
      final String? home = usable(environment['HOME']);
      return home == null
          ? null
          : '$home/Library/Application Support/$appId/dartvel-crashes';
    case 'windows':
      final String? base =
          usable(environment['LOCALAPPDATA']) ?? usable(environment['APPDATA']);
      return base == null ? null : '$base\\$appId\\dartvel-crashes';
    default:
      final String? data = usable(environment['XDG_DATA_HOME']);
      if (data != null) return '$data/$appId/dartvel-crashes';
      final String? home = usable(environment['HOME']);
      return home == null ? null : '$home/.local/share/$appId/dartvel-crashes';
  }
}

final RegExp _installIdShape = RegExp(r'^[0-9a-f]{32}$');

/// This install's id: the stored one, or a new random one stored for next
/// time.
///
/// Random and install-scoped — not a user, not an advertising id — so it is
/// gone when the application is reinstalled or its data cleared, as the
/// specification says. A stored value that is not an id is replaced rather
/// than trusted: whatever was written there would ride along on every
/// report. Storage that cannot be read or written still yields an id, for
/// this run only, rather than failing the installation.
String dvInstallIdFrom({
  required String? Function() read,
  required void Function(String id) write,
  String Function()? generate,
}) {
  try {
    final String? stored = read()?.trim();
    if (stored != null && _installIdShape.hasMatch(stored)) return stored;
  } on Object {
    // Unreadable: a new id below.
  }
  final String id = (generate ?? dvAnalyticsRandomId)();
  try {
    write(id);
  } on Object {
    // Unwritable: this run still has an id.
  }
  return id;
}
