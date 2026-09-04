/// Whether an Android SDK is installed, asked the way Flutter asks it.
///
/// The check was `sdkmanager` on PATH. A GitHub runner ships an Android SDK
/// and does not put sdkmanager on PATH; Android Studio installs one that only
/// its own shell knows about. So `dartvel build android` refused on machines
/// that build Android perfectly well, and the refusal told the person to
/// install the SDK they already had — which is the worst kind of refusal,
/// because there is nothing to act on.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether [path] holds an Android SDK.
///
/// A `platforms` directory with something in it, rather than the directory
/// merely existing: ANDROID_HOME pointing at an empty or half-deleted folder
/// is common, and reading that as an SDK turns a clear refusal into a Gradle
/// error twenty lines long.
bool dvAndroidSdkAt(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  final Directory platforms = Directory(p.join(path, 'platforms'));
  if (!platforms.existsSync()) return false;
  return platforms.listSync().whereType<Directory>().isNotEmpty;
}

/// Whether this machine can build for Android.
///
/// [environment] and [onPath] are injected so the answer can be tested
/// without one, which is the whole difficulty with a check about what is
/// installed.
bool dvAndroidSdkInstalled({
  Map<String, String>? environment,
  bool Function(String tool)? onPath,
}) {
  final Map<String, String> env = environment ?? Platform.environment;
  // Both, because Flutter reads both and which one is set depends on how the
  // SDK was installed.
  for (final String name in const <String>['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    if (dvAndroidSdkAt(env[name])) return true;
  }
  // The old answer was not wrong, only incomplete.
  final bool Function(String) resolves = onPath ?? _isOnPath;
  return resolves('sdkmanager');
}

bool _isOnPath(String tool) {
  try {
    return Process.runSync(
          Platform.isWindows ? 'where' : 'which',
          <String>[tool],
          runInShell: true,
        ).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}
