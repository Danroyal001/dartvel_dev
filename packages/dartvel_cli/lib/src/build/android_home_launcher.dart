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
const String _banner = ' android:banner="@mipmap/ic_launcher"';

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
  String out = _strip(_strip(manifest, _filterStart, _filterEnd), _queriesStart, _queriesEnd).replaceFirst(_banner, '');
  if (!enabled) return out;

  // The TV app row shows a banner; without one it shows nothing. The app's
  // icon, unless the application already names a banner of its own.
  final int app = out.indexOf('<application');
  if (app >= 0 && !out.substring(app, out.indexOf('>', app)).contains('android:banner=')) {
    out = out.replaceFirst('<application', '<application$_banner');
  }

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
      // Android TV lists apps that answer LEANBACK_LAUNCHER in its app row.
      '            <intent-filter>\n'
      '                <action android:name="android.intent.action.MAIN"/>\n'
      '                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>\n'
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
      // A TV has no touchscreen; required features would keep it off one.
      '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n'
      '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n'
      '$_queriesEnd\n';
  return '${out.substring(0, applicationLine)}$queries${out.substring(applicationLine)}';
}

// The wallpaper. A home app sits on the phone's wallpaper: the window asks
// for it (windowShowWallpaper) and draws no background of its own, from the
// first instant (LaunchTheme) and after (NormalTheme), and Flutter's surface
// is transparent so the frame does not paint over it. Without the first, the
// time between pressing home and the first frame is a black screen.

const String _styleStart = '        <!-- dartvel.android.launcher wallpaper: begin -->';
const String _styleEnd = '        <!-- dartvel.android.launcher wallpaper: end -->';
const String _styleBlock = '$_styleStart\n'
    '        <item name="android:windowShowWallpaper">true</item>\n'
    '        <item name="android:windowBackground">@android:color/transparent</item>\n'
    '$_styleEnd\n';

/// Flutter's own window backgrounds, put back when the setting is turned off.
const Map<String, String> _flutterBackgrounds = <String, String>{
  'LaunchTheme': '@drawable/launch_background',
  'NormalTheme': '?android:colorBackground',
};

/// [styles] (a res/values*/styles.xml) with LaunchTheme and NormalTheme
/// showing the wallpaper, or with Flutter's backgrounds when [enabled] is
/// false.
String dvAndroidHomeLauncherStyles(String styles, {required bool enabled}) {
  String out = _strip(styles, _styleStart, _styleEnd);
  for (final MapEntry<String, String> theme in _flutterBackgrounds.entries) {
    final RegExpMatch? open = RegExp('<style\\s+name="${theme.key}"[^>]*>').firstMatch(out);
    if (open == null) continue;
    final int close = out.indexOf('</style>', open.end);
    if (close < 0) continue;
    String body = out.substring(open.end, close);
    final RegExp background = RegExp(r'\n[ \t]*<item\s+name="android:windowBackground">[^<]*</item>');
    if (enabled) {
      body = body.replaceAll(background, '');
      final int closeLine = body.lastIndexOf('\n') + 1;
      body = '${body.substring(0, closeLine)}$_styleBlock${body.substring(closeLine)}';
    } else if (!background.hasMatch(body)) {
      final int closeLine = body.lastIndexOf('\n') + 1;
      body = '${body.substring(0, closeLine)}        <item name="android:windowBackground">${theme.value}</item>\n${body.substring(closeLine)}';
    }
    out = '${out.substring(0, open.end)}$body${out.substring(close)}';
  }
  return out;
}

const String _flutterActivityLine = 'class MainActivity : FlutterActivity()';
const String _transparentActivity = 'class MainActivity : FlutterActivity() {\n'
    '    // dartvel.android.launcher: the phone\'s wallpaper shows through the app.\n'
    '    override fun getBackgroundMode(): io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode =\n'
    '        io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode.transparent\n'
    '\n'
    '    // The home app is never closed by Back: Back on its first page does nothing,\n'
    '    // as on every launcher, and the next press of home is not a cold start.\n'
    '    override fun popSystemNavigator(): Boolean = true\n'
    '}';

/// [activity] (MainActivity.kt) with a transparent Flutter surface, or as
/// Flutter wrote it when [enabled] is false. Null when [enabled] and the
/// activity is not Flutter's own any more: Dartvel does not rewrite an
/// activity someone has changed.
String? dvAndroidHomeLauncherActivity(String activity, {required bool enabled}) {
  final bool ours = activity.contains(_transparentActivity);
  if (!enabled) return ours ? activity.replaceFirst(_transparentActivity, _flutterActivityLine) : activity;
  if (ours) return activity;
  final RegExp plain = RegExp('^${RegExp.escape(_flutterActivityLine)}[ \\t]*\$', multiLine: true);
  if (!plain.hasMatch(activity)) return null;
  return activity.replaceFirst(plain, _transparentActivity);
}
