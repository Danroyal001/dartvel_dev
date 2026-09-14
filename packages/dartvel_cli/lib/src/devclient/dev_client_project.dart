/// What a project's dev-client shell is built from, and the plan to build it.
///
/// The binding manifest is read from what Flutter resolved rather than from
/// anything declared by hand: `.flutter-plugins-dependencies` lists the native
/// plugins compiled for each platform, and `pubspec.lock` the dartvel_flutter
/// version whose FFI/JNI bindings and renderer the shell carries. The same
/// function produces the shell's manifest at build time and a bundle's at
/// serve time, so the two can only differ by what changed in between.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVDevClientManifest;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Store-signed targets a shell is built for.
///
/// Desktop and embedded targets have no store identity for a shell to collide
/// with, and the section gives them a launch flag instead; that flag is not
/// built.
const List<String> dvDevClientTargets = <String>['android', 'ios'];

/// Where `dartvel dev` reads the page documents it serves.
const String dvDevClientPagesDir = 'studio/pages';

/// The generated shell entrypoint, relative to the project.
const String dvDevClientEntrypoint = '.dart_tool/dartvel/dev_client_main.dart';

/// The flavor a shell is built under, so it takes its own application id.
const String dvDevClientFlavor = 'devclient';

/// Why a manifest could not be resolved.
class DVDevClientProjectException implements Exception {
  const DVDevClientProjectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The binding manifest of the project at [root] for [target].
///
/// Throws [DVDevClientProjectException] when the plugins were never resolved:
/// an empty manifest would load into any shell, including one missing every
/// plugin the project uses.
DVDevClientManifest dvProjectDevClientManifest(String root, String target) {
  final File resolved = File(p.join(root, '.flutter-plugins-dependencies'));
  if (!resolved.existsSync()) {
    throw const DVDevClientProjectException(
      'This project\'s plugins have not been resolved, so which native '
      'bindings it needs is unknown. Run `flutter pub get` first.',
    );
  }
  final Object? document;
  try {
    document = jsonDecode(resolved.readAsStringSync());
  } on FormatException {
    throw const DVDevClientProjectException(
      '.flutter-plugins-dependencies is not JSON. Run `flutter pub get` '
      'again.',
    );
  }
  final Object? plugins = document is Map ? document['plugins'] : null;
  final Object? forTarget = plugins is Map ? plugins[target] : null;
  final List<String> bindings = <String>[
    if (forTarget is List)
      for (final Object? plugin in forTarget)
        if (plugin is Map &&
            plugin['native_build'] != false &&
            plugin['dev_dependency'] != true &&
            plugin['name'] is String)
          'plugin:${plugin['name']}',
  ];
  final String? runtime = _lockedVersion(root, 'dartvel_flutter');
  if (runtime != null) bindings.add('dartvel_flutter@$runtime');
  return DVDevClientManifest(
    target: target,
    bindings: bindings.toSet().toList()..sort(),
  );
}

String? _lockedVersion(String root, String package) {
  final File lock = File(p.join(root, 'pubspec.lock'));
  if (!lock.existsSync()) return null;
  try {
    final Object? document = loadYaml(lock.readAsStringSync());
    final Object? packages = document is Map ? document['packages'] : null;
    final Object? entry = packages is Map ? packages[package] : null;
    final Object? version = entry is Map ? entry['version'] : null;
    return version == null ? null : '$version';
  } on Object {
    return null;
  }
}

/// The address a device on the same network should be told to use.
///
/// A private LAN address first -- that is where a phone on the office Wi-Fi
/// can reach -- then any other non-loopback, non-link-local address, and
/// loopback only when nothing else exists.
String dvDevClientAdvertisedHost(List<InternetAddress> addresses) {
  bool private(InternetAddress a) {
    final List<int> b = a.rawAddress;
    if (a.type != InternetAddressType.IPv4) return false;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168);
  }

  bool usable(InternetAddress a) =>
      !a.isLoopback && !a.isLinkLocal && a.type == InternetAddressType.IPv4;

  for (final InternetAddress a in addresses) {
    if (private(a)) return a.address;
  }
  for (final InternetAddress a in addresses) {
    if (usable(a)) return a.address;
  }
  return InternetAddress.loopbackIPv4.address;
}

/// How a shell for one target is built, or why it cannot be.
class DVDevClientBuildPlan {
  const DVDevClientBuildPlan({
    required this.target,
    required this.manifest,
    required this.executable,
    required this.arguments,
    required this.entrypointPath,
    required this.entrypointSource,
  }) : problems = const <String>[];

  const DVDevClientBuildPlan.refused(this.target, this.problems)
    : manifest = const DVDevClientManifest(target: '', bindings: <String>[]),
      executable = '',
      arguments = const <String>[],
      entrypointPath = '',
      entrypointSource = '';

  final String target;
  final DVDevClientManifest manifest;
  final String executable;
  final List<String> arguments;
  final String entrypointPath;
  final String entrypointSource;
  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// The plan for a [target] shell of the project at [root].
///
/// Target, then host, then tooling, then what the project declares -- and
/// every refusal before a file is written, per the build toolchain rule. The
/// Android SDK and Xcode are never fetched.
DVDevClientBuildPlan dvDevClientBuildPlan({
  required String root,
  required String target,
  required String host,
  required bool Function(String tool) onPath,
  required bool androidSdkInstalled,
}) {
  if (!dvDevClientTargets.contains(target)) {
    return DVDevClientBuildPlan.refused(target, <String>[
      'A dev-client shell is built for ${dvDevClientTargets.join(' or ')}. '
          '"$target" is not one of them; desktop and embedded targets have no '
          'store identity to collide with, and a dev-client launch flag for '
          'them is not built.',
    ]);
  }
  if (target == 'ios' && host != 'macos') {
    return DVDevClientBuildPlan.refused(target, <String>[
      'An iOS shell needs Xcode, so it is built on macOS. This is $host.',
    ]);
  }

  final List<String> problems = <String>[
    if (!onPath('flutter'))
      'flutter is not on PATH, and the shell is a Flutter build.',
    if (target == 'android' && !androidSdkInstalled)
      'No Android SDK was found (ANDROID_HOME, ANDROID_SDK_ROOT or '
          'sdkmanager). Dartvel does not install it; install it with Android '
          'Studio or the command-line tools and run this again.',
    if (target == 'ios' && !onPath('xcodebuild'))
      'xcodebuild is not on PATH. Install Xcode; Dartvel does not.',
  ];
  if (problems.isNotEmpty) {
    return DVDevClientBuildPlan.refused(target, problems);
  }

  if (!_declaresFlavor(root, target)) {
    problems.add(
      target == 'android'
          ? 'android/app/build.gradle declares no "$dvDevClientFlavor" product '
                'flavor with an applicationIdSuffix. Without one the shell takes '
                'the application\'s id and installs over it on a tester\'s phone.'
          : 'ios/Runner.xcodeproj has no "$dvDevClientFlavor" scheme. Without '
                'one the shell takes the application\'s bundle id and installs '
                'over it.',
    );
  }
  DVDevClientManifest? manifest;
  try {
    manifest = dvProjectDevClientManifest(root, target);
  } on DVDevClientProjectException catch (error) {
    problems.add(error.message);
  }
  if (problems.isNotEmpty || manifest == null) {
    return DVDevClientBuildPlan.refused(target, problems);
  }

  final String entrypoint = p.join(root, dvDevClientEntrypoint);
  return DVDevClientBuildPlan(
    target: target,
    manifest: manifest,
    executable: 'flutter',
    arguments: <String>[
      'build',
      if (target == 'android') 'apk' else 'ipa',
      '--release',
      '--flavor',
      dvDevClientFlavor,
      '-t',
      entrypoint,
    ],
    entrypointPath: entrypoint,
    entrypointSource: dvDevClientEntrypointSource(manifest),
  );
}

bool _declaresFlavor(String root, String target) {
  if (target == 'android') {
    for (final String name in const <String>[
      'build.gradle.kts',
      'build.gradle',
    ]) {
      final File file = File(p.join(root, 'android', 'app', name));
      if (!file.existsSync()) continue;
      final String source = file.readAsStringSync();
      if (source.contains(dvDevClientFlavor) &&
          source.contains('applicationIdSuffix')) {
        return true;
      }
    }
    return false;
  }
  return File(
    p.join(
      root,
      'ios',
      'Runner.xcodeproj',
      'xcshareddata',
      'xcschemes',
      '$dvDevClientFlavor.xcscheme',
    ),
  ).existsSync();
}

/// The shell's `main`: the recorded manifest, the platform's bindings, and
/// no application code.
String dvDevClientEntrypointSource(DVDevClientManifest manifest) {
  final String bindings = manifest.normalizedBindings
      .map((String b) => "    '${b.replaceAll("'", r"\'")}',")
      .join('\n');
  final String register = manifest.target == 'android'
      ? 'DVAndroidBindings.register()'
      : 'DVIosBindings.register()';
  return '''
// GENERATED by `dartvel build dev-client`. Do not edit.
//
// A dev-client shell: the engine, this project's native bindings, and no
// application code. It is the only entrypoint that imports
// package:dartvel_flutter/dev_client.dart.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/dev_client.dart';
import 'package:flutter/widgets.dart';

const DVDevClientManifest _manifest = DVDevClientManifest(
  target: '${manifest.target}',
  bindings: <String>[
$bindings
  ],
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  $register;
  DV.Database.configure(SqliteDVDatabaseAdapter.memory());
  runApp(const DVDevClientShell(manifest: _manifest));
}
''';
}
