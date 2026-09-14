/// Where a device keeps its own analytics database.
library dartvel_core.analytics.analytics_directory;

/// The directory [appId]'s analytics database goes in on [os], or null when
/// the platform gives no directory that survives a restart.
///
/// `DARTVEL_ANALYTICS_DIR` wins everywhere. The rest is the per-user data
/// directory each platform keeps across reboots, by the rules crash records
/// follow: Android's files directory (it sets no HOME), Application Support
/// on Apple platforms, LOCALAPPDATA on Windows, XDG elsewhere. Never the
/// temporary directory, which the system clears -- a consent store that
/// disappears asks the person again every launch -- and null rather than a
/// relative guess, which on a device resolves against `/`.
///
/// [androidStateDirectory] is the device runtime's directory inside the
/// application's files directory.
String? dvAnalyticsDirectoryFor({
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

  final String? declared = usable(environment['DARTVEL_ANALYTICS_DIR']);
  if (declared != null) return declared;

  const String leaf = 'dartvel-analytics';
  switch (os) {
    case 'android':
      final String? state = usable(androidStateDirectory);
      if (state == null) return null;
      final int slash = state.lastIndexOf('/');
      final String? files =
          slash <= 0 ? null : usable(state.substring(0, slash));
      return files == null ? null : '$files/$leaf';
    case 'ios':
    case 'macos':
      final String? home = usable(environment['HOME']);
      return home == null
          ? null
          : '$home/Library/Application Support/$appId/$leaf';
    case 'windows':
      final String? base =
          usable(environment['LOCALAPPDATA']) ?? usable(environment['APPDATA']);
      return base == null ? null : '$base\\$appId\\$leaf';
    default:
      final String? data = usable(environment['XDG_DATA_HOME']);
      if (data != null) return '$data/$appId/$leaf';
      final String? home = usable(environment['HOME']);
      return home == null ? null : '$home/.local/share/$appId/$leaf';
  }
}
