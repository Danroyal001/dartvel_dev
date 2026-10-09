/// `dartvel build horizon` and `dartvel build visionos`: the two headsets a
/// Dartvel application reaches today, both as a 2D panel.
///
/// **Meta Horizon OS** runs Android apps as panels. The target is the Android
/// build with what the Horizon Store requires of a panel app written into the
/// manifest, built 64-bit at the SDK levels Meta names, and then checked: the
/// built APK is read back with `aapt2` and refused when it breaks a rule the
/// store's upload check would. Sources, all Meta's:
///
/// - https://developers.meta.com/horizon/resources/publish-mobile-manifest/
///   (head tracking not required for a panel app, `com.oculus.supportedDevices`,
///   minSdk 29-34, targetSdk 34 for apps created since 2026-03-01,
///   `installLocation` auto)
/// - https://developers.meta.com/horizon/documentation/android-apps/create-app/
///   (`<layout android:defaultWidth="1024dp" android:defaultHeight="640dp"/>`)
/// - https://developers.meta.com/horizon/resources/permissions-prohibited/
///
/// **visionOS** has no Flutter embedder (flutter/flutter#128313 is open and
/// the Flutter team has said it is not planned). Apple runs iPad apps on
/// Vision Pro unchanged, "Designed for iPad", so the target is the iOS build:
/// https://developer.apple.com/documentation/visionos/making-your-app-compatible-with-visionos
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVXRConfig;
import 'package:path/path.dart' as p;

/// The headset targets.
const List<String> spatialBuildPlatforms = <String>['horizon', 'visionos'];

/// The native project a target writes into and builds from.
///
/// Horizon OS is an Android build and visionOS an iOS one, so every writer
/// that prepares `android/` or `ios/` -- splash, launcher identity, deep
/// links, file storage -- prepares it for them too.
String dvNativeProjectFor(String platform) => switch (platform) {
      'horizon' => 'android',
      'visionos' => 'ios',
      _ => platform,
    };

/// Meta's recommended minimum, inside the 29-34 range it accepts.
const int dvHorizonMinSdk = 32;

/// What Meta requires of every app created since 2026-03-01.
const int dvHorizonTargetSdk = 34;

/// The Gradle properties the Horizon build hands Flutter's Android project.
const String dvHorizonMinSdkProperty = 'dartvelMinSdk';
const String dvHorizonTargetSdkProperty = 'dartvelTargetSdk';

/// The ABIs every native library is packaged for. `--target-platform`
/// limits Flutter's own code and nothing else: a plugin's libraries, such as
/// the `jni` package's libdartjni.so, came for armeabi-v7a and x86_64 too, and
/// the APK check refused the first Horizon build for it.
const String dvHorizonAbiFiltersProperty = 'dartvelAbiFilters';

/// What `flutter build apk` is given for a Horizon build, after the mode.
List<String> dvHorizonFlutterArguments() => const <String>[
      // The store takes 64-bit apps, and every Quest is arm64.
      '--target-platform',
      'android-arm64',
      '--android-project-arg=$dvHorizonMinSdkProperty=$dvHorizonMinSdk',
      '--android-project-arg=$dvHorizonTargetSdkProperty=$dvHorizonTargetSdk',
      '--android-project-arg=$dvHorizonAbiFiltersProperty=arm64-v8a',
    ];

const String _begin = '<!-- dartvel.horizon: begin -->';
const String _end = '<!-- dartvel.horizon: end -->';
const String _installLocation = ' android:installLocation="auto"';

/// [manifest] with the Horizon OS panel-app entries in it, or without them
/// when [enabled] is false.
///
/// Every entry is in a marked block, so a second build replaces it and an
/// Android build after a Horizon one gets back exactly the manifest Flutter
/// wrote. A panel app gets no `com.oculus.intent.category.VR`: that category
/// launches an OpenXR app, and this one has nothing to draw there.
String dvHorizonManifest(String manifest, DVXRConfig config, {required bool enabled}) {
  final RegExp block = RegExp('\n[ \t]*${RegExp.escape(_begin)}.*?${RegExp.escape(_end)}', dotAll: true);
  String out = manifest.replaceAll(block, '');
  out = out.replaceAllMapped(RegExp('<manifest([^>]*?)${RegExp.escape(_installLocation)}'),
      (Match match) => '<manifest${match[1]}');
  if (!enabled) return out;

  // installLocation is an attribute of <manifest>, which a comment cannot
  // mark; it is removed above by its exact text.
  out = out.replaceFirstMapped(RegExp(r'<manifest([^>]*)>'),
      (Match match) => '<manifest${match[1]}$_installLocation>');

  final int manifestOpen = out.indexOf('>', out.indexOf('<manifest')) + 1;
  out = '${out.substring(0, manifestOpen)}\n'
      '    $_begin\n'
      '    <!-- A panel app runs without 6DoF tracking; required="true" is for immersive apps. -->\n'
      '    <uses-feature android:name="android.hardware.vr.headtracking" android:required="false" android:version="1"/>\n'
      '    $_end'
      '${out.substring(manifestOpen)}';

  final RegExpMatch? activity =
      RegExp(r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>').firstMatch(out);
  if (activity != null) {
    final String size = <String>[
      'android:defaultWidth="${config.panel.width}dp"',
      'android:defaultHeight="${config.panel.height}dp"',
      if (config.panel.minWidth != null) 'android:minWidth="${config.panel.minWidth}dp"',
      if (config.panel.minHeight != null) 'android:minHeight="${config.panel.minHeight}dp"',
    ].join(' ');
    out = '${out.substring(0, activity.end)}\n'
        '            $_begin\n'
        '            <layout $size/>\n'
        '            $_end'
        '${out.substring(activity.end)}';
  }

  final int close = out.lastIndexOf('</application>');
  if (close >= 0) {
    final int lineStart = out.lastIndexOf('\n', close) + 1;
    out = '${out.substring(0, lineStart)}'
        '        $_begin\n'
        '        <meta-data android:name="com.oculus.supportedDevices" android:value="${config.horizonSupportedDevices}"/>\n'
        '        $_end\n'
        '${out.substring(lineStart)}';
  }
  return out;
}

/// [gradle] with `minSdk` and `targetSdk` read from the Gradle properties a
/// Horizon build passes, falling back to Flutter's own values.
///
/// Written once and left in: without the properties -- every Android build
/// -- the values are exactly what Flutter's template set. Null when the file
/// has neither form Flutter's template writes, rather than a guess at
/// someone else's build file.
String? dvHorizonGradle(String gradle) {
  String out = gradle;
  final bool kotlin = out.contains('minSdk = flutter.minSdkVersion') ||
      out.contains('findProperty("$dvHorizonMinSdkProperty")');
  final bool groovy = out.contains('minSdkVersion flutter.minSdkVersion') ||
      out.contains("findProperty('$dvHorizonMinSdkProperty')");
  if (!kotlin && !groovy) return null;
  if (kotlin) {
    out = out
        .replaceFirst('minSdk = flutter.minSdkVersion',
            'minSdk = (project.findProperty("$dvHorizonMinSdkProperty") as String?)?.toInt() ?: flutter.minSdkVersion')
        .replaceFirst('targetSdk = flutter.targetSdkVersion',
            'targetSdk = (project.findProperty("$dvHorizonTargetSdkProperty") as String?)?.toInt() ?: flutter.targetSdkVersion');
  } else {
    out = out
        .replaceFirst('minSdkVersion flutter.minSdkVersion',
            "minSdkVersion project.findProperty('$dvHorizonMinSdkProperty')?.toInteger() ?: flutter.minSdkVersion")
        .replaceFirst('targetSdkVersion flutter.targetSdkVersion',
            "targetSdkVersion project.findProperty('$dvHorizonTargetSdkProperty')?.toInteger() ?: flutter.targetSdkVersion");
  }
  // The ABI filter, after the targetSdk line inside defaultConfig, once.
  // Without the property nothing is filtered, as Flutter's template had it.
  if (!out.contains(dvHorizonAbiFiltersProperty)) {
    final RegExpMatch? target =
        RegExp(r'^([ \t]*)targetSdk(?:Version)?\b.*$', multiLine: true).firstMatch(out);
    if (target == null) return null;
    final String indent = target[1]!;
    final String filter = kotlin
        ? '$indent(project.findProperty("$dvHorizonAbiFiltersProperty") as String?)?.let { abis ->\n'
            '$indent    ndk { abiFilters.clear(); abiFilters.addAll(abis.split(",")) }\n'
            '$indent}'
        : "${indent}if (project.findProperty('$dvHorizonAbiFiltersProperty')) {\n"
            "$indent    ndk { abiFilters(*project.findProperty('$dvHorizonAbiFiltersProperty').split(',')) }\n"
            '$indent}';
    out = '${out.substring(0, target.end)}\n$filter${out.substring(target.end)}';
  }
  return out;
}

/// The permissions the Horizon Store's upload check refuses, as Meta lists
/// them (without the `android.permission.` prefix). Meta says the list is
/// common rather than exhaustive and may change.
/// https://developers.meta.com/horizon/resources/permissions-prohibited/
const Set<String> dvHorizonProhibitedPermissions = <String>{
  'ACCEPT_HANDOVER', 'ACCESS_BACKGROUND_LOCATION', 'ACCESS_CHECKIN_PROPERTIES',
  'ACCESS_LOCATION_EXTRA_COMMANDS', 'ACCESS_NOTIFICATION_POLICY', 'ACCOUNT_MANAGER',
  'ACTIVITY_RECOGNITION', 'ADD_VOICEMAIL', 'ANSWER_PHONE_CALLS',
  'BIND_ACCESSIBILITY_SERVICE', 'BIND_APPWIDGET', 'BIND_AUTOFILL_SERVICE',
  'BIND_CALL_REDIRECTION_SERVICE', 'BIND_CARRIER_MESSAGING_CLIENT_SERVICE',
  'BIND_CARRIER_MESSAGING_SERVICE', 'BIND_CARRIER_SERVICES',
  'BIND_CHOOSER_TARGET_SERVICE', 'BIND_CONDITION_PROVIDER_SERVICE', 'BIND_CONTROLS',
  'BIND_DEVICE_ADMIN', 'BIND_DREAM_SERVICE', 'BIND_INCALL_SERVICE', 'BIND_INPUT_METHOD',
  'BIND_MIDI_DEVICE_SERVICE', 'BIND_NFC_SERVICE', 'BIND_NOTIFICATION_LISTENER_SERVICE',
  'BIND_PRINT_SERVICE', 'BIND_QUICK_ACCESS_WALLET_SERVICE', 'BIND_QUICK_SETTINGS_TILE',
  'BIND_REMOTEVIEWS', 'BIND_SCREENING_SERVICE', 'BIND_TELECOM_CONNECTION_SERVICE',
  'BIND_TEXT_SERVICE', 'BIND_TV_INPUT', 'BIND_VISUAL_VOICEMAIL_SERVICE',
  'BIND_VOICE_INTERACTION', 'BIND_VR_LISTENER_SERVICE', 'BIND_WALLPAPER',
  'BLUETOOTH_PRIVILEGED', 'BODY_SENSORS', 'BROADCAST_PACKAGE_REMOVED', 'BROADCAST_SMS',
  'BROADCAST_WAP_PUSH', 'CALL_PHONE', 'CALL_PRIVILEGED', 'CAPTURE_AUDIO_OUTPUT',
  'CHANGE_COMPONENT_ENABLED_STATE', 'CHANGE_CONFIGURATION', 'CLEAR_APP_CACHE',
  'CONTROL_LOCATION_UPDATES', 'DELETE_CACHE_FILES', 'DELETE_PACKAGES', 'DIAGNOSTIC',
  'DUMP', 'FACTORY_TEST', 'GET_ACCOUNTS', 'GET_ACCOUNTS_PRIVILEGED',
  'INSTALL_LOCATION_PROVIDER', 'INSTALL_PACKAGES', 'INSTANT_APP_FOREGROUND_SERVICE',
  'LOADER_USAGE_STATS', 'LOCATION_HARDWARE', 'MANAGE_DOCUMENTS', 'MANAGE_MEDIA',
  'MANAGE_ONGOING_CALLS', 'MASTER_CLEAR', 'MEDIA_CONTENT_CONTROL', 'MODIFY_PHONE_STATE',
  'MOUNT_FORMAT_FILESYSTEMS', 'MOUNT_UNMOUNT_FILESYSTEMS', 'PACKAGE_USAGE_STATS',
  'PROCESS_OUTGOING_CALLS', 'QUERY_ALL_PACKAGES', 'READ_CALENDAR', 'READ_CALL_LOG',
  'READ_CONTACTS', 'READ_INPUT_STATE', 'READ_LOGS', 'READ_PHONE_NUMBERS',
  'READ_PHONE_STATE', 'READ_PRECISE_PHONE_STATE', 'READ_SMS', 'READ_VOICEMAIL', 'REBOOT',
  'RECEIVE_MMS', 'RECEIVE_SMS', 'RECEIVE_WAP_PUSH', 'REQUEST_DELETE_PACKAGES',
  'REQUEST_INSTALL_PACKAGES', 'SEND_RESPOND_VIA_MESSAGE', 'SEND_SMS', 'SET_ALWAYS_FINISH',
  'SET_ANIMATION_SCALE', 'SET_DEBUG_APP', 'SET_PROCESS_LIMIT', 'SET_TIME', 'SET_TIME_ZONE',
  'SIGNAL_PERSISTENT_PROCESSES', 'SMS_FINANCIAL_TRANSACTIONS',
  'START_FOREGROUND_SERVICES_FROM_BACKGROUND', 'START_VIEW_PERMISSION_USAGE',
  'STATUS_BAR', 'SYSTEM_ALERT_WINDOW', 'UNINSTALL_SHORTCUT', 'UPDATE_DEVICE_STATS',
  'USB_CAMERA', 'USE_ICC_AUTH_WITH_DEVICE_IDENTIFIER', 'USE_SIP', 'UWB_RANGING',
  'WRITE_APN_SETTINGS', 'WRITE_CALENDAR', 'WRITE_CALL_LOG', 'WRITE_CONTACTS',
  'WRITE_GSERVICES', 'WRITE_SECURE_SETTINGS', 'WRITE_SETTINGS', 'WRITE_VOICEMAIL',
};

/// Why the APK described by [badging] (`aapt2 dump badging`) and
/// [manifestTree] (`aapt2 dump xmltree --file AndroidManifest.xml`) would
/// not be accepted as a Horizon OS panel app, one sentence each. Empty when
/// it would.
///
/// Read from the built APK rather than the source manifest, because the
/// merged manifest is what the store sees: a plugin can add a permission or
/// raise an SDK level the project never wrote.
List<String> dvHorizonApkProblems({
  required String badging,
  required String manifestTree,
  required DVXRConfig config,
}) {
  final List<String> problems = <String>[];
  int? level(String key) {
    final RegExpMatch? match = RegExp("^$key:'(\\d+)'", multiLine: true).firstMatch(badging);
    return match == null ? null : int.parse(match[1]!);
  }

  final int? target = level('targetSdkVersion');
  if (target != dvHorizonTargetSdk) {
    problems.add('targetSdkVersion $target: Meta requires $dvHorizonTargetSdk for apps created since 2026-03-01.');
  }
  final int? minimum = level('minSdkVersion') ?? level('sdkVersion');
  if (minimum == null || minimum < 29 || minimum > 34) {
    problems.add('minSdkVersion $minimum: Horizon OS takes 29 to 34.');
  }
  if (RegExp(r"^\s*uses-feature: name='android\.hardware\.vr\.headtracking'", multiLine: true).hasMatch(badging)) {
    problems.add('android.hardware.vr.headtracking is required: a panel app must not require it, '
        'or it is listed as an immersive app.');
  }
  if (!badging.contains("install-location:'auto'")) {
    problems.add('installLocation is not auto, which the Horizon Store requires.');
  }
  for (final RegExpMatch match
      in RegExp(r"^uses-permission: name='(?:android\.permission\.)?([A-Z_]+)'", multiLine: true).allMatches(badging)) {
    if (dvHorizonProhibitedPermissions.contains(match[1])) {
      problems.add('android.permission.${match[1]} is prohibited on the Horizon Store; '
          'find the plugin that adds it and remove it from this build.');
    }
  }
  final RegExpMatch? native = RegExp(r'^native-code:(.*)$', multiLine: true).firstMatch(badging);
  if (native != null) {
    for (final RegExpMatch abi in RegExp(r"'([^']+)'").allMatches(native[1]!)) {
      if (abi[1] != 'arm64-v8a') {
        problems.add('native code for ${abi[1]}: Quest headsets are arm64-v8a only.');
      }
    }
  }
  final RegExpMatch? devices = RegExp(
          r'"com\.oculus\.supportedDevices"[^\n]*\n[^\n]*android:value\([^)]*\)="([^"]*)"')
      .firstMatch(manifestTree);
  if (devices == null) {
    problems.add('com.oculus.supportedDevices is missing, so the store does not know which headsets to list it for.');
  } else if (devices[1] != config.horizonSupportedDevices) {
    problems.add('com.oculus.supportedDevices is "${devices[1]}", and dartvel.xr declares '
        '"${config.horizonSupportedDevices}".');
  }
  if (!RegExp(r'E: layout[^\n]*\n[^\n]*defaultWidth').hasMatch(manifestTree)) {
    problems.add('the main activity has no <layout> default size, so the panel opens at whatever size the OS picks.');
  }
  if (manifestTree.contains('com.oculus.intent.category.VR')) {
    problems.add('com.oculus.intent.category.VR is for immersive OpenXR apps; a panel app launched with it has nothing to draw.');
  }
  return problems;
}

/// `aapt2` from the newest build-tools of the Android SDK in [environment],
/// or null when there is none.
///
/// Gradle needs build-tools to package an APK at all, so after a Horizon
/// build this is there; the SDK is looked for the way Flutter looks for it.
String? dvLocateAapt2({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  for (final String name in const <String>['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final String? sdk = env[name];
    if (sdk == null || sdk.isEmpty) continue;
    final Directory tools = Directory(p.join(sdk, 'build-tools'));
    if (!tools.existsSync()) continue;
    final List<Directory> versions = tools.listSync().whereType<Directory>().toList()
      ..sort((Directory a, Directory b) => _compareVersions(p.basename(b.path), p.basename(a.path)));
    for (final Directory version in versions) {
      final File aapt2 = File(p.join(version.path, Platform.isWindows ? 'aapt2.exe' : 'aapt2'));
      if (aapt2.existsSync()) return aapt2.path;
    }
  }
  return null;
}

/// Orders `35.0.0` before `36.0.0` and `36.0.0` before `36.0.0-rc1`'s
/// release, numerically rather than as text, so `9.0.0` is not newest.
int _compareVersions(String left, String right) {
  List<int> parts(String version) => <int>[
        for (final String part in version.split(RegExp(r'[.\-]')))
          int.tryParse(part) ?? -1,
      ];
  final List<int> a = parts(left);
  final List<int> b = parts(right);
  for (int index = 0; index < a.length && index < b.length; index++) {
    if (a[index] != b[index]) return a[index].compareTo(b[index]);
  }
  return a.length.compareTo(b.length);
}

/// Where `flutter build apk` writes the APK for [buildMode] (`--release`).
String dvHorizonApkPath(String root, String buildMode) => p.join(
    root, 'build', 'app', 'outputs', 'flutter-apk', 'app-${buildMode.replaceFirst('--', '')}.apk');
