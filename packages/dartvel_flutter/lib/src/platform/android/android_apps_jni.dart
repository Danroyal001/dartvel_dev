/// The installed apps that can be launched, through PackageManager, and
/// opening one. Backs `DV.Platform.apps` (DVApps) on Android.
///
/// Android 11 hides other packages from an app unless its manifest declares
/// what it queries; `dartvel.android.launcher: true` writes the MAIN/LAUNCHER
/// `<queries>` entry these calls depend on. Without it the list comes back
/// with only the app itself, which is a well-formed wrong answer.
library dartvel_flutter.platform.android.apps;

import 'dart:typed_data';

import 'package:jni/jni.dart';

import 'generated/android/app/Activity.dart';
import 'generated/android/content/Context.dart';
import 'generated/android/content/Intent.dart';
import 'generated/android/content/pm/ActivityInfo.dart';
import 'generated/android/content/pm/ComponentInfo.dart';
import 'generated/android/content/pm/PackageItemInfo.dart';
import 'generated/android/content/pm/PackageManager.dart';
import 'generated/android/content/pm/ResolveInfo.dart';
import 'generated/android/graphics/drawable/Drawable.dart';
import 'generated/android/graphics/Bitmap.dart';
import 'generated/android/graphics/Canvas.dart';
import 'generated/android/net/Uri.dart';
import 'generated/java/io/ByteArrayOutputStream.dart';

/// The square an icon is drawn into: big enough for a 4x grid on a phone,
/// small enough that a hundred of them are not a hundred large PNGs.
const int dvAndroidAppIconSize = 144;

/// Settings.ACTION_APPLICATION_DETAILS_SETTINGS. A constant on a class the
/// bindings do not otherwise need, so it is written out.
const String _appDetailsAction = 'android.settings.APPLICATION_DETAILS_SETTINGS';

/// RoleManager.createRequestRoleIntent(ROLE_HOME), written out: the same
/// action and extra, answered by the system's permission controller on
/// Android 10 and later, which shows its own "set as default home app?"
/// question. Written out because RoleManager is one class for two strings.
const String _requestRoleAction = 'android.app.role.action.REQUEST_ROLE';
const String _roleNameExtra = 'android.app.role.extra.ROLE_NAME';
const String _homeRole = 'android.app.role.HOME';

/// Settings.ACTION_HOME_SETTINGS and ACTION_MANAGE_DEFAULT_APPS_SETTINGS: the
/// Home app chooser, and the default-apps page that holds it, for phones
/// older than Android 10 or without the role question.
const List<String> _homeSettingsActions = <String>['android.settings.HOME_SETTINGS', 'android.settings.MANAGE_DEFAULT_APPS_SETTINGS'];

/// startActivityForResult's code. Nothing reads the result: the app asks
/// isDefaultLauncher again when it is resumed, which is also right when the
/// person changes the home app later in Settings.
const int _homeRoleRequestCode = 0x484F;

class DVAndroidApps {
  const DVAndroidApps._();

  /// Every activity that answers MAIN/LAUNCHER, one entry per package, as
  /// `{package, label, icon?}` maps (icon as PNG bytes).
  static List<Map<String, Object?>> list(Context context, {required bool icons}) {
    final pm = context.packageManager;
    if (pm == null) return const <Map<String, Object?>>[];
    final launchable = Intent.new$2(Intent.ACTION_MAIN)..addCategory(Intent.CATEGORY_LAUNCHER);
    final found = pm.queryIntentActivities(launchable, 0);
    if (found == null) return const <Map<String, Object?>>[];
    final Map<String, Map<String, Object?>> byPackage = <String, Map<String, Object?>>{};
    for (final ResolveInfo? info in found.asDart()) {
      if (info == null) continue;
      final String? package = info.activityInfo?.packageName?.toDartString(releaseOriginal: true);
      // One icon per app. Some apps register several launcher activities;
      // the first is the one the system drawer shows first.
      if (package == null || package.isEmpty || byPackage.containsKey(package)) continue;
      final String label = info.loadLabel(pm)?.toString() ?? '';
      byPackage[package] = <String, Object?>{
        'package': package,
        'label': label,
        if (icons) 'icon': _icon(info, pm),
      };
    }
    return byPackage.values.toList();
  }

  /// The app's launcher icon drawn into a square bitmap and compressed to PNG,
  /// or null when the drawable cannot be drawn.
  static Uint8List? _icon(ResolveInfo info, PackageManager pm) {
    try {
      final drawable = info.loadIcon(pm);
      if (drawable == null) return null;
      final bitmap = Bitmap.createBitmap$3(dvAndroidAppIconSize, dvAndroidAppIconSize, Bitmap$Config.ARGB_8888);
      if (bitmap == null) return null;
      final canvas = Canvas.new$1(bitmap);
      drawable.setBounds(0, 0, dvAndroidAppIconSize, dvAndroidAppIconSize);
      drawable.draw(canvas);
      final out = ByteArrayOutputStream();
      if (!bitmap.compress(Bitmap$CompressFormat.PNG, 100, out)) return null;
      final bytes = out.toByteArray();
      if (bytes == null) return null;
      final Int8List signed = bytes.getRange(0, bytes.length);
      bitmap.recycle();
      return Uint8List.fromList(signed.buffer.asUint8List(signed.offsetInBytes, signed.length));
    } on Object {
      // An icon that will not draw is a missing icon, not a missing app.
      return null;
    }
  }

  /// [package]'s launcher icon as PNG bytes, or null when it has none that
  /// draws.
  static Uint8List? icon(Context context, String package) {
    final pm = context.packageManager;
    if (pm == null || package.isEmpty) return null;
    final launch = pm.getLaunchIntentForPackage(package.toJString());
    if (launch == null) return null;
    final info = pm.resolveActivity(launch, 0);
    if (info == null) return null;
    return _icon(info, pm);
  }

  /// The intent each role is answered for: what the phone opens to call, to
  /// text, to show a web page, to take a picture, to write an email and to
  /// show a place. The launcher manifest's <queries> declares each one, or
  /// Android 11+ hides the apps that answer them.
  static Intent? _roleIntent(String role) {
    Intent withData(JString? action, String data) => Intent.new$3(action, Uri.parse(data.toJString()));
    return switch (role) {
      'phone' => withData(Intent.ACTION_DIAL, 'tel:'),
      'messages' => withData(Intent.ACTION_SENDTO, 'smsto:'),
      'browser' => withData(Intent.ACTION_VIEW, 'https://example.com')..addCategory(Intent.CATEGORY_BROWSABLE),
      'camera' => Intent.new$2('android.media.action.STILL_IMAGE_CAMERA'.toJString()),
      'email' => withData(Intent.ACTION_SENDTO, 'mailto:'),
      'maps' => withData(Intent.ACTION_VIEW, 'geo:0,0?q='),
      _ => null,
    };
  }

  /// The package the phone opens for [role]: the default the person chose,
  /// else the first app that answers it, else null. With no default Android
  /// resolves to its own chooser (package "android"), which is not an app.
  static String? defaultFor(Context context, String role) {
    final pm = context.packageManager;
    final intent = _roleIntent(role);
    if (pm == null || intent == null) return null;
    final String? chosen = pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName?.toDartString(releaseOriginal: true);
    if (chosen != null && chosen.isNotEmpty && chosen != 'android') return chosen;
    final found = pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY);
    if (found == null) return null;
    for (final ResolveInfo? info in found.asDart()) {
      final String? package = info?.activityInfo?.packageName?.toDartString(releaseOriginal: true);
      if (package != null && package.isNotEmpty && package != 'android') return package;
    }
    return null;
  }

  /// Whether the activity the home button opens belongs to this app.
  static bool isDefaultLauncher(Context context) {
    final pm = context.packageManager;
    if (pm == null) return false;
    final home = Intent.new$2(Intent.ACTION_MAIN)..addCategory(Intent.CATEGORY_HOME);
    final String? holder = pm.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName?.toDartString(releaseOriginal: true);
    final String? self = context.packageName?.toDartString(releaseOriginal: true);
    return holder != null && holder == self;
  }

  /// Asks to become the home app, and true once a screen for it has opened.
  ///
  /// The Home app settings come first: every phone has them, and the
  /// person sees where to choose. The role question is the fallback, because
  /// some vendors' Android (Tecno's HiOS among them) refuse it without
  /// showing anything, which reads as a button that does nothing.
  ///
  /// Each screen is started and its failure caught, not looked up first:
  /// from Android 11 a lookup answers "none" for a system screen this app may
  /// not see, which would make the button do nothing.
  static bool requestDefaultLauncher(Context context, Activity? activity) {
    for (final String action in _homeSettingsActions) {
      try {
        context.startActivity(Intent.new$2(action.toJString())..addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        return true;
      } on Object {
        // This phone has no such screen; try the next.
      }
    }
    if (activity != null) {
      try {
        final role = Intent.new$2(_requestRoleAction.toJString())..putExtra$8(_roleNameExtra.toJString(), _homeRole.toJString());
        activity.startActivityForResult(role, _homeRoleRequestCode);
        return true;
      } on Object {
        // No role question on this phone either.
      }
    }
    try {
      context.startActivity(Intent.new$2('android.settings.SETTINGS'.toJString())..addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
      return true;
    } on Object {
      return false;
    }
  }


  /// Starts [package] the way tapping its icon would. False when the package
  /// is gone or has no launcher activity.
  static bool open(Context context, String package) {
    final intent = context.packageManager?.getLaunchIntentForPackage(package.toJString());
    if (intent == null) return false;
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    context.startActivity(intent);
    return true;
  }

  /// The system's info page for [package].
  static bool openSettings(Context context, String package) =>
      _start(context, _appDetailsAction.toJString(), package);

  /// The system's uninstall confirmation for [package].
  static bool uninstall(Context context, String package) =>
      _start(context, Intent.ACTION_DELETE, package);

  static bool _start(Context context, JString? action, String package) {
    final uri = Uri.parse('package:$package'.toJString());
    if (action == null || uri == null) return false;
    final intent = Intent.new$3(action, uri)..addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    context.startActivity(intent);
    return true;
  }
}
