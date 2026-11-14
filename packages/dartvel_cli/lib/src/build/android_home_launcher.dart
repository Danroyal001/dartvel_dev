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
      '        <!-- The other home apps: without them isDefaultLauncher sees only itself. -->\n'
      '        <intent><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.HOME"/></intent>\n'
      '        <!-- The apps behind each dock role (DV.Platform.apps.defaultFor). -->\n'
      '        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>\n'
      '        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="smsto"/></intent>\n'
      '        <intent><action android:name="android.intent.action.VIEW"/><category android:name="android.intent.category.BROWSABLE"/><data android:scheme="https"/></intent>\n'
      '        <intent><action android:name="android.media.action.STILL_IMAGE_CAMERA"/></intent>\n'
      '        <intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>\n'
      '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="geo"/></intent>\n'
      '        <!-- The screens that choose the home app (requestDefaultLauncher). -->\n'
      '        <intent><action android:name="android.settings.HOME_SETTINGS"/></intent>\n'
      '        <intent><action android:name="android.settings.MANAGE_DEFAULT_APPS_SETTINGS"/></intent>\n'
      '        <intent><action android:name="android.app.role.action.REQUEST_ROLE"/></intent>\n'
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

/// The res folders whose styles.xml carries the window themes: light and dark,
/// and from API 31 (Android 12) the launch theme's own files.
const List<String> dvAndroidHomeLauncherStylesFolders = <String>['values', 'values-night', 'values-v31', 'values-night-v31'];

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
const String _wallpaperAndBack = '    // dartvel.android.launcher: the phone\'s wallpaper shows through the app.\n'
    '    override fun getBackgroundMode(): io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode =\n'
    '        io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode.transparent\n'
    '\n'
    '    // The home app is never closed by Back: Back on its first page does nothing,\n'
    '    // as on every launcher, and the next press of home is not a cold start.\n'
    '    override fun popSystemNavigator(): Boolean = true\n';
const String _transparentActivity = 'class MainActivity : FlutterActivity() {\n'
    '$_wallpaperAndBack'
    '\n'
    '    // What the system tells a home app, told to the app as it happens over the\n'
    '    // channel DVApps listens on: Home, Recents, and the signals around them\n'
    '    // (DV.Platform.apps.homeAppSignals). Android 10 and later neither pause nor\n'
    '    // resume a home app that is already in front when Home is pressed, so the\n'
    '    // app cannot wait for a resume to find out. The Home and Recents stamps are\n'
    '    // kept on the intent too, for a press the engine was not there to hear.\n'
    '    companion object {\n'
    '        // The running activity, for the opt-in Recents service in this process.\n'
    '        @JvmStatic var dartvelCurrent: MainActivity? = null\n'
    '    }\n'
    '\n'
    '    fun dartvelSystemKey(name: String, pressedAt: Long = android.os.SystemClock.elapsedRealtime(), detail: String = "") {\n'
    '        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return\n'
    '        io.flutter.plugin.common.BasicMessageChannel(messenger, "dev.dartvel/system_keys", io.flutter.plugin.common.StringCodec.INSTANCE)\n'
    '            .send(if (detail.isEmpty()) "\$name:\$pressedAt" else "\$name:\$pressedAt:\$detail")\n'
    '    }\n'
    '\n'
    '    // Home pressed while the home app is in front (or bringing it back) arrives\n'
    '    // as a new intent and nothing else. DV.Platform.apps.homePresses hears it,\n'
    '    // so a launcher can close its drawer and go back to its first page. The\n'
    '    // opt-in Recents service brings the app forward the same way, naming why.\n'
    '    override fun onNewIntent(intent: android.content.Intent) {\n'
    '        val pressedAt = android.os.SystemClock.elapsedRealtime()\n'
    '        val recentsFrom = intent.getStringExtra("dev.dartvel.recentsFrom")\n'
    '        if (recentsFrom != null) {\n'
    '            intent.putExtra("dev.dartvel.recentsPressedAt", pressedAt)\n'
    '            setIntent(intent)\n'
    '            dartvelSystemKey("recentsReplaced", pressedAt, recentsFrom)\n'
    '        } else if (intent.hasCategory(android.content.Intent.CATEGORY_HOME)) {\n'
    '            intent.putExtra("dev.dartvel.homePressedAt", pressedAt)\n'
    '            setIntent(intent)\n'
    '            dartvelSystemKey("home", pressedAt)\n'
    '        }\n'
    '        super.onNewIntent(intent)\n'
    '    }\n'
    '\n'
    '    // ACTION_CLOSE_SYSTEM_DIALOGS, with its reason ("recentapps", "homekey",\n'
    '    // "assist"...), heard for as long as the app runs. Where the phone\'s own\n'
    '    // launcher sends "recentapps" for the Recents button and then shows\n'
    '    // nothing over another home app (HiOS can), DV.Platform.apps.recentsPresses\n'
    '    // lets the app show its own Recents.\n'
    '    private val dartvelSystemKeys = object : android.content.BroadcastReceiver() {\n'
    '        override fun onReceive(context: android.content.Context, broadcast: android.content.Intent) {\n'
    '            val pressedAt = android.os.SystemClock.elapsedRealtime()\n'
    '            val reason = broadcast.getStringExtra("reason") ?: ""\n'
    '            dartvelSystemKey("closeSystemDialogs", pressedAt, reason)\n'
    '            if (reason == "recentapps") {\n'
    '                intent?.putExtra("dev.dartvel.recentsPressedAt", pressedAt)\n'
    '                dartvelSystemKey("recents", pressedAt)\n'
    '            }\n'
    '        }\n'
    '    }\n'
    '\n'
    '    override fun onCreate(savedInstanceState: android.os.Bundle?) {\n'
    '        super.onCreate(savedInstanceState)\n'
    '        dartvelCurrent = this\n'
    '        val filter = android.content.IntentFilter(android.content.Intent.ACTION_CLOSE_SYSTEM_DIALOGS)\n'
    '        if (android.os.Build.VERSION.SDK_INT >= 33) {\n'
    '            registerReceiver(dartvelSystemKeys, filter, android.content.Context.RECEIVER_NOT_EXPORTED)\n'
    '        } else {\n'
    '            registerReceiver(dartvelSystemKeys, filter)\n'
    '        }\n'
    '    }\n'
    '\n'
    '    override fun onDestroy() {\n'
    '        try { unregisterReceiver(dartvelSystemKeys) } catch (alreadyGone: IllegalArgumentException) {}\n'
    '        if (dartvelCurrent === this) dartvelCurrent = null\n'
    '        super.onDestroy()\n'
    '    }\n'
    '\n'
    '    // What the app asks the activity: whether the person turned the opt-in\n'
    '    // Recents service on, and the settings page where they do.\n'
    '    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {\n'
    '        super.configureFlutterEngine(flutterEngine)\n'
    '        io.flutter.plugin.common.BasicMessageChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.dartvel/home_app", io.flutter.plugin.common.StringCodec.INSTANCE)\n'
    '            .setMessageHandler { question, reply ->\n'
    '                when (question) {\n'
    '                    "recentsService.isOn" -> {\n'
    '                        val on = android.provider.Settings.Secure.getString(contentResolver, "enabled_accessibility_services") ?: ""\n'
    '                        reply.reply(if (on.split(\':\').any { it.startsWith("\$packageName/") && it.endsWith("DartvelRecentsService") }) "true" else "false")\n'
    '                    }\n'
    '                    "recentsService.settings" -> {\n'
    '                        val declared = try {\n'
    '                            packageManager.getServiceInfo(android.content.ComponentName(packageName, "\$packageName.DartvelRecentsService"), 0); true\n'
    '                        } catch (notBuilt: android.content.pm.PackageManager.NameNotFoundException) { false }\n'
    '                        if (declared) startActivity(android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))\n'
    '                        reply.reply(if (declared) "true" else "false")\n'
    '                    }\n'
    '                    else -> reply.reply(null)\n'
    '                }\n'
    '            }\n'
    '    }\n'
    '\n'
    '    override fun onPause() {\n'
    '        dartvelSystemKey("pause")\n'
    '        super.onPause()\n'
    '    }\n'
    '\n'
    '    override fun onStop() {\n'
    '        dartvelSystemKey("stop")\n'
    '        super.onStop()\n'
    '    }\n'
    '\n'
    '    override fun onUserLeaveHint() {\n'
    '        dartvelSystemKey("userLeaveHint")\n'
    '        super.onUserLeaveHint()\n'
    '    }\n'
    '\n'
    '    override fun onWindowFocusChanged(hasFocus: Boolean) {\n'
    '        super.onWindowFocusChanged(hasFocus)\n'
    '        dartvelSystemKey("focus", detail = if (hasFocus) "gained" else "lost")\n'
    '    }\n'
    '\n'
    '    // Back reached the activity (before Flutter and the app answer it).\n'
    '    @Suppress("OVERRIDE_DEPRECATION")\n'
    '    override fun onBackPressed() {\n'
    '        dartvelSystemKey("back")\n'
    '        super.onBackPressed()\n'
    '    }\n'
    '}';

/// The activity Dartvel 0.13.51 wrote: it stamped Home and Recents on the
/// intent and left the app to read the stamp on a resume Android never sends.
const String _activity01351 = 'class MainActivity : FlutterActivity() {\n'
    '$_wallpaperAndBack'
    '\n'
    '    // Home pressed while the home app is in front (or bringing it back) arrives\n'
    '    // as a new intent and nothing else. Stamped here and kept as the intent,\n'
    '    // DV.Platform.apps.homePresses reads it when the app resumes, so a launcher\n'
    '    // can close its drawer and go back to its first page.\n'
    '    override fun onNewIntent(intent: android.content.Intent) {\n'
    '        if (intent.hasCategory(android.content.Intent.CATEGORY_HOME)) {\n'
    '            intent.putExtra("dev.dartvel.homePressedAt", android.os.SystemClock.elapsedRealtime())\n'
    '            setIntent(intent)\n'
    '        }\n'
    '        super.onNewIntent(intent)\n'
    '    }\n'
    '\n'
    '    // The Recents button pressed while the home app is in front. Some phones\n'
    '    // (HiOS among them) host Recents in their own launcher and show nothing\n'
    '    // when another app is the home app; the press still arrives as the\n'
    '    // system\'s "recentapps" broadcast. Stamped on the intent for\n'
    '    // DV.Platform.apps.recentsPresses, so the app can show its own recent apps.\n'
    '    private val dartvelSystemKeys = object : android.content.BroadcastReceiver() {\n'
    '        override fun onReceive(context: android.content.Context, broadcast: android.content.Intent) {\n'
    '            if (broadcast.getStringExtra("reason") == "recentapps") {\n'
    '                intent?.putExtra("dev.dartvel.recentsPressedAt", android.os.SystemClock.elapsedRealtime())\n'
    '            }\n'
    '        }\n'
    '    }\n'
    '\n'
    '    override fun onStart() {\n'
    '        super.onStart()\n'
    '        val filter = android.content.IntentFilter(android.content.Intent.ACTION_CLOSE_SYSTEM_DIALOGS)\n'
    '        if (android.os.Build.VERSION.SDK_INT >= 33) {\n'
    '            registerReceiver(dartvelSystemKeys, filter, android.content.Context.RECEIVER_NOT_EXPORTED)\n'
    '        } else {\n'
    '            registerReceiver(dartvelSystemKeys, filter)\n'
    '        }\n'
    '    }\n'
    '\n'
    '    override fun onStop() {\n'
    '        try { unregisterReceiver(dartvelSystemKeys) } catch (alreadyGone: IllegalArgumentException) {}\n'
    '        super.onStop()\n'
    '    }\n'
    '}';


/// [_activity01351], for the test that an activity it wrote is updated.
const String dvAndroidHomeLauncherActivity01351ForTest = _activity01351;

/// What earlier Dartvel versions wrote, recognised as Dartvel's own so a
/// build brings it up to date rather than reporting it as someone's edit.
const List<String> _earlierActivities = <String>[
  'class MainActivity : FlutterActivity() {\n$_wallpaperAndBack}',
  _activity01351,
];

/// [activity] (MainActivity.kt) with a transparent Flutter surface, or as
/// Flutter wrote it when [enabled] is false. Null when [enabled] and the
/// activity is not Flutter's own any more: Dartvel does not rewrite an
/// activity someone has changed.
String? dvAndroidHomeLauncherActivity(String activity, {required bool enabled}) {
  for (final String earlier in _earlierActivities) {
    if (activity.contains(earlier)) activity = activity.replaceFirst(earlier, _transparentActivity);
  }
  final bool ours = activity.contains(_transparentActivity);
  if (!enabled) return ours ? activity.replaceFirst(_transparentActivity, _flutterActivityLine) : activity;
  if (ours) return activity;
  final RegExp plain = RegExp('^${RegExp.escape(_flutterActivityLine)}[ \\t]*\$', multiLine: true);
  if (!plain.hasMatch(activity)) return null;
  return activity.replaceFirst(plain, _transparentActivity);
}

// The opt-in Recents service. A home app can never be the phone's Recents:
// that is the system's own or the phone maker's launcher
// (config_recentsComponentName), and the Recents button goes to it. An
// accessibility service the person turns on once in Settings can see the
// Recents key, the Recents button being pressed, or the system's Recents
// window opening, and bring the home app forward to show its own instead.

const String _serviceStart = '        <!-- dartvel.android.recentsService: begin -->';
const String _serviceEnd = '        <!-- dartvel.android.recentsService: end -->';

/// Whether `dartvel.android.recentsService` is true in [dartvel], on an app
/// that is also a home app (`dartvel.android.launcher: true`).
bool dvAndroidRecentsServiceEnabled(Map<Object?, Object?> dartvel) {
  final Object? android = dartvel['android'];
  return android is Map && android['launcher'] == true && android['recentsService'] == true;
}

/// [manifest] with the Recents service declared in `<application>`, or
/// without it when [enabled] is false.
String dvAndroidRecentsServiceManifest(String manifest, {required bool enabled}) {
  final String out = _strip(manifest, _serviceStart, _serviceEnd);
  if (!enabled) return out;
  final int close = out.indexOf('</application>');
  if (close < 0) return out;
  final int closeLine = out.lastIndexOf('\n', close) + 1;
  const String service = '$_serviceStart\n'
      '        <service\n'
      '            android:name=".DartvelRecentsService"\n'
      '            android:exported="true"\n'
      '            android:label="@string/dartvel_recents_service_label"\n'
      '            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">\n'
      '            <intent-filter>\n'
      '                <action android:name="android.accessibilityservice.AccessibilityService"/>\n'
      '            </intent-filter>\n'
      '            <meta-data android:name="android.accessibilityservice" android:resource="@xml/dartvel_recents_service"/>\n'
      '        </service>\n'
      '$_serviceEnd\n';
  return '${out.substring(0, closeLine)}$service${out.substring(closeLine)}';
}

/// res/xml/dartvel_recents_service.xml: what the service asks the system for.
/// Window changes and clicks (the Recents window opening, the Recents button)
/// and key events (the Recents key, where the phone sends it). It never asks
/// to read what is on the screen.
const String dvAndroidRecentsServiceConfig = '<?xml version="1.0" encoding="utf-8"?>\n'
    '<!-- Written by dartvel build (dartvel.android.recentsService). -->\n'
    '<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"\n'
    '    android:accessibilityEventTypes="typeWindowStateChanged|typeViewClicked"\n'
    '    android:accessibilityFeedbackType="feedbackGeneric"\n'
    '    android:accessibilityFlags="flagRequestFilterKeyEvents"\n'
    '    android:canRequestFilterKeyEvents="true"\n'
    '    android:notificationTimeout="0"\n'
    '    android:description="@string/dartvel_recents_service_description"\n'
    '    android:summary="@string/dartvel_recents_service_summary"/>\n';

/// res/values/dartvel_recents_service.xml: what Settings shows the person
/// before they turn the service on. [appName] is the app's own name.
String dvAndroidRecentsServiceStrings(String appName) {
  final String name = appName.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll("'", r"\'").replaceAll('"', r'\"');
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<!-- Written by dartvel build (dartvel.android.recentsService). -->\n'
      '<resources>\n'
      '    <string name="dartvel_recents_service_label">$name Recents</string>\n'
      '    <string name="dartvel_recents_service_summary">Show $name\\\'s recent apps when you press Recents</string>\n'
      '    <string name="dartvel_recents_service_description">While $name is your home app, pressing the Recents button shows $name\\\'s own recent apps instead of the phone\\\'s. It only notices the Recents button and which window opens. It does not read what is on your screen or what you type.</string>\n'
      '</resources>\n';
}

/// DartvelRecentsService.kt, in the app's [package], beside its MainActivity.
String dvAndroidRecentsServiceSource(String package) => 'package $package\n'
    '\n'
    '// Written by dartvel build (dartvel.android.recentsService). Edits are replaced.\n'
    '//\n'
    '// While this app is the phone\'s home app, the Recents button shows the app\'s\n'
    '// own Recents: this service sees the Recents key, the Recents button pressed\n'
    '// or the system\'s Recents window opening, and brings the app forward. It\n'
    '// also tells the app each window that opens, for a diagnostics screen.\n'
    'class DartvelRecentsService : android.accessibilityservice.AccessibilityService() {\n'
    '    // The phone names its own Recents; nothing is guessed per brand.\n'
    '    private val systemRecents: String? by lazy {\n'
    '        val system = android.content.res.Resources.getSystem()\n'
    '        val id = system.getIdentifier("config_recentsComponentName", "string", "android")\n'
    '        if (id == 0) null else android.content.ComponentName.unflattenFromString(system.getString(id))?.packageName\n'
    '    }\n'
    '    private var replacedAt = 0L\n'
    '\n'
    '    private fun isHomeApp(): Boolean {\n'
    '        val home = android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_HOME)\n'
    '        return packageManager.resolveActivity(home, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName == packageName\n'
    '    }\n'
    '\n'
    '    private fun showOurRecents(from: String) {\n'
    '        val now = android.os.SystemClock.elapsedRealtime()\n'
    '        // One press can be seen three ways (key, button, window): answer once.\n'
    '        if (now - replacedAt < 1500 || !isHomeApp()) return\n'
    '        replacedAt = now\n'
    '        startActivity(\n'
    '            android.content.Intent(this, MainActivity::class.java)\n'
    '                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP or android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)\n'
    '                .putExtra("dev.dartvel.recentsFrom", from)\n'
    '        )\n'
    '    }\n'
    '\n'
    '    override fun onKeyEvent(event: android.view.KeyEvent): Boolean {\n'
    '        if (event.keyCode != android.view.KeyEvent.KEYCODE_APP_SWITCH || !isHomeApp()) return false\n'
    '        if (event.action == android.view.KeyEvent.ACTION_UP) showOurRecents("key")\n'
    '        return true\n'
    '    }\n'
    '\n'
    '    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent) {\n'
    '        val from = event.packageName?.toString() ?: return\n'
    '        val what = event.className?.toString() ?: ""\n'
    '        if (event.eventType == android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {\n'
    '            MainActivity.dartvelCurrent?.dartvelSystemKey("window", detail = "\$from/\$what")\n'
    '            if (from != packageName && from == systemRecents && what.contains("Recents")) showOurRecents("window")\n'
    '        } else if (event.eventType == android.view.accessibility.AccessibilityEvent.TYPE_VIEW_CLICKED && from == "com.android.systemui") {\n'
    '            val label = event.contentDescription?.toString() ?: event.text.joinToString(" ")\n'
    '            MainActivity.dartvelCurrent?.dartvelSystemKey("click", detail = "\$from/\$label")\n'
    '            if (label == systemUiText("accessibility_recent")) showOurRecents("button")\n'
    '        }\n'
    '    }\n'
    '\n'
    '    // The Recents button\'s own name, in the phone\'s language, from System UI.\n'
    '    private fun systemUiText(name: String): String? = try {\n'
    '        val resources = packageManager.getResourcesForApplication("com.android.systemui")\n'
    '        val id = resources.getIdentifier(name, "string", "com.android.systemui")\n'
    '        if (id == 0) null else resources.getString(id)\n'
    '    } catch (notThere: android.content.pm.PackageManager.NameNotFoundException) { null }\n'
    '\n'
    '    override fun onInterrupt() {}\n'
    '}\n';
