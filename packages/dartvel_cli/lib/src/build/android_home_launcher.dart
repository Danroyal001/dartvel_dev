/// `dartvel.android.launcher: true`: the app can be chosen as the phone's
/// home screen.
///
/// Android lists an app under Settings > Apps > Default apps > Home app only
/// when its launcher activity also answers MAIN with the HOME and DEFAULT
/// categories. And from Android 11 an app sees other installed apps only after
/// it declares, in `<queries>`, which ones it looks for; a launcher that does
/// not declare MAIN/LAUNCHER sees an empty drawer. The native folders are
/// build output, so both have to come from pubspec.yaml or a launcher cannot
/// be built with Dartvel at all.
///
/// Both blocks are marked, as the app-shortcuts block is, so a later build
/// replaces them and turning the setting off removes them.
library dartvel_cli.build.android_home_launcher;

const String _filterStart = '            <!-- dartvel.android.launcher: begin -->';
const String _filterEnd = '            <!-- dartvel.android.launcher: end -->';
const String _queriesStart = '    <!-- dartvel.android.launcher queries: begin -->';
const String _queriesEnd = '    <!-- dartvel.android.launcher queries: end -->';

/// Whether `dartvel.android.launcher` is true in [dartvel] (the `dartvel:` map
/// from pubspec.yaml).
bool dvAndroidHomeLauncherEnabled(Map<Object?, Object?> dartvel) {
  final Object? android = dartvel['android'];
  return android is Map && android['launcher'] == true;
}

String _strip(String manifest, String start, String end) =>
    manifest.replaceAll(RegExp('\n${RegExp.escape(start)}.*?${RegExp.escape(end)}', dotAll: true), '');

/// [manifest] with the HOME intent filter in its launcher activity and the
/// `<queries>` declaration, or with neither when [enabled] is false.
String dvAndroidHomeLauncherManifest(String manifest, {required bool enabled}) {
  String out = _strip(_strip(manifest, _filterStart, _filterEnd), _queriesStart, _queriesEnd);
  if (!enabled) return out;

  // The HOME filter, inside the activity that already answers LAUNCHER.
  final int launcher = out.indexOf('android.intent.category.LAUNCHER');
  if (launcher < 0) return out;
  final int close = out.indexOf('</activity>', launcher);
  if (close < 0) return out;
  final int closeLine = out.lastIndexOf('\n', close) + 1;
  const String filter = '$_filterStart\n'
      '            <intent-filter>\n'
      '                <action android:name="android.intent.action.MAIN"/>\n'
      '                <category android:name="android.intent.category.HOME"/>\n'
      '                <category android:name="android.intent.category.DEFAULT"/>\n'
      '            </intent-filter>\n'
      '$_filterEnd\n';
  out = '${out.substring(0, closeLine)}$filter${out.substring(closeLine)}';

  // <queries> belongs to <manifest>, before <application>.
  final int application = out.indexOf('<application');
  if (application < 0) return out;
  final int applicationLine = out.lastIndexOf('\n', application) + 1;
  const String queries = '$_queriesStart\n'
      '    <queries>\n'
      '        <intent>\n'
      '            <action android:name="android.intent.action.MAIN"/>\n'
      '            <category android:name="android.intent.category.LAUNCHER"/>\n'
      '        </intent>\n'
      '    </queries>\n'
      '$_queriesEnd\n';
  return '${out.substring(0, applicationLine)}$queries${out.substring(applicationLine)}';
}
