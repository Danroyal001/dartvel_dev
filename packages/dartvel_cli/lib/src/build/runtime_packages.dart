/// Finding the package that provides a runtime the framework does not ship.
///
/// A runtime is code that runs inside the application or its server rather
/// than at build time: a host the app is embedded in (a messenger mini-app, a
/// browser extension), a spatial presentation backend behind `DV.Window`, a
/// terminal surface, a sign-in provider for a host's credentials. Each is
/// plugged into a public extension point of the framework
/// (`DVPlatformHost`, `DVWindowSpaceBackend`, `DVAttachedSurface`,
/// `AuthProvider`, `DVStoreAdapter`); this file is how a project's generated
/// code finds and installs the package that provides them.
///
/// A runtime package carries a `dartvel_runtimes.yaml` at its root:
///
/// ```yaml
/// runtimes: [telegram, xr, terminal, browser-extension]
/// client:
///   import: package:acme_runtimes/acme_runtimes.dart
///   install: dvInstallAcmeRuntimes     # void Function(Map<String, Object?> sections)
///   terminal_surface: DVTerminalSurface.attach()   # an expression yielding a DVAttachedSurface
/// server:
///   import: package:acme_runtimes/server.dart
///   auth_providers:
///     telegram: dvTelegramAuthProvider()           # an expression yielding an AuthProvider
/// ```
///
/// Dart cannot load code into a running executable, so nothing is loaded: the
/// generated code imports the package, which the project depends on.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The manifest a runtime package carries at its root.
const String dvRuntimeManifestFile = 'dartvel_runtimes.yaml';

/// A package in the project's dependencies that provides runtimes.
class DVRuntimePackage {
  const DVRuntimePackage({
    required this.name,
    required this.root,
    required this.runtimes,
    this.clientImport,
    this.clientInstall,
    this.terminalSurface,
    this.serverImport,
    this.authProviders = const <String, String>{},
  });

  final String name;
  final String root;

  /// Every runtime the manifest names.
  final List<String> runtimes;

  /// The library the generated client imports, and the function in it that
  /// installs the runtimes with the project's `dartvel:` sections.
  final String? clientImport;
  final String? clientInstall;

  /// An expression the terminal-only client attaches its surface with.
  final String? terminalSurface;

  /// The library the generated backend imports, and, per `dartvel:` section,
  /// the expression that builds its sign-in provider.
  final String? serverImport;
  final Map<String, String> authProviders;
}

/// The runtime packages [projectRoot] depends on, read from its
/// `.dart_tool/package_config.json`. Empty before `pub get` has run, and for
/// a package whose manifest cannot be read.
List<DVRuntimePackage> dvRuntimePackages(String projectRoot) {
  final File config =
      File(p.join(projectRoot, '.dart_tool', 'package_config.json'));
  if (!config.existsSync()) return const <DVRuntimePackage>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(config.readAsStringSync());
  } on FormatException {
    return const <DVRuntimePackage>[];
  }
  final Object? packages = decoded is Map ? decoded['packages'] : null;
  if (packages is! List) return const <DVRuntimePackage>[];
  final List<DVRuntimePackage> found = <DVRuntimePackage>[];
  for (final Object? entry in packages) {
    if (entry is! Map) continue;
    final Object? name = entry['name'];
    final Object? rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String) continue;
    final Uri resolved = config.parent.uri
        .resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
    if (resolved.scheme != 'file') continue;
    final DVRuntimePackage? package =
        dvReadRuntimeManifest(name, p.normalize(resolved.toFilePath()));
    if (package != null) found.add(package);
  }
  return found;
}

/// The manifest of the package [name] at [root], or null when it has none or
/// it is not one Dartvel can read.
DVRuntimePackage? dvReadRuntimeManifest(String name, String root) {
  final File manifest = File(p.join(root, dvRuntimeManifestFile));
  if (!manifest.existsSync()) return null;
  final Object? yaml;
  try {
    yaml = loadYaml(manifest.readAsStringSync());
  } on Object {
    return null;
  }
  if (yaml is! Map || yaml['runtimes'] is! List) return null;
  final Object? client = yaml['client'];
  final Object? server = yaml['server'];
  String? text(Object? section, String key) =>
      section is Map && section[key] is String ? section[key] as String : null;
  final Object? providers = server is Map ? server['auth_providers'] : null;
  return DVRuntimePackage(
    name: name,
    root: root,
    runtimes: <String>[for (final Object? runtime in yaml['runtimes'] as List) '$runtime'],
    clientImport: text(client, 'import'),
    clientInstall: text(client, 'install'),
    terminalSurface: text(client, 'terminal_surface'),
    serverImport: text(server, 'import'),
    authProviders: <String, String>{
      if (providers is Map)
        for (final MapEntry<Object?, Object?> entry in providers.entries)
          if (entry.value is String) '${entry.key}': entry.value as String,
    },
  );
}

/// The package that provides [runtime] to [projectRoot], or null.
DVRuntimePackage? dvRuntimePackageFor(String projectRoot, String runtime) {
  for (final DVRuntimePackage package in dvRuntimePackages(projectRoot)) {
    if (package.runtimes.contains(runtime)) return package;
  }
  return null;
}

/// Runtimes that need a paid Dartvel Cloud plan, each with what it is.
///
/// They are provided by the `dartvel_runtimes_pro` package, which comes with
/// any Cloud plan; the CLI knows only their names, so that using one on a free
/// install says what it is and how to get it. Releases 0.11.5 and earlier
/// shipped them in the open and remain MIT licensed.
const Map<String, String> dvPaidRuntimes = <String, String>{
  'telegram': 'Telegram Mini App runtime: host frame, sign-in, Stars purchases',
  'xr': 'XR runtime behind DV.Window: volumes and immersive spaces',
  'terminal': 'terminal surface for -cli and -tui builds',
  'browser-extension': 'browser extension runtime: manifest, messaging, storage',
};

/// The package that implements [dvPaidRuntimes].
const String dvRuntimesProPackage = 'dartvel_runtimes_pro';

/// The paid runtimes a `dartvel:` section of the pubspec asks for.
///
/// Only the sections whose meaning is a runtime: `dartvel.telegram` configures
/// the Telegram runtime and does nothing without it, which would be a silent
/// no-op if the build did not say so.
List<String> dvRuntimesRequiredBy(Object? dartvelSection) {
  if (dartvelSection is! Map) return const <String>[];
  return <String>[
    if (dartvelSection['telegram'] != null) 'telegram',
  ];
}

/// What the build says when [runtime] is needed and no package provides it.
String dvRuntimeRefusal(String runtime, {String? because}) {
  final String? what = dvPaidRuntimes[runtime];
  return <String>[
    '${because ?? 'This project uses the $runtime runtime'}'
        '${what == null ? '' : ' ($what)'}, which is a paid runtime: it is '
        'included in every Dartvel Cloud plan and is not part of the free '
        'install.',
    '',
    '  Add it to this project: dartvel targets add runtimes',
    '    which adds the $dvRuntimesProPackage package. It is fetched from a '
        'private repository that comes with a Cloud plan.',
    '  Or build on Dartvel Cloud: add --cloud to the build.',
    '',
    'Every free target (Android, iOS, web and web-server, Windows, macOS, '
        'Linux, embedded Linux and the TV platforms) builds and runs without '
        'it. Releases 0.11.5 and earlier included these runtimes and remain '
        'MIT licensed.',
  ].join('\n');
}

/// The refusal for the first paid runtime [dartvelSection] needs that no
/// package in [projectRoot] provides, or null when everything is covered.
String? dvRuntimeRefusalFor(String projectRoot, Object? dartvelSection) {
  for (final String runtime in dvRuntimesRequiredBy(dartvelSection)) {
    if (dvRuntimePackageFor(projectRoot, runtime) == null) {
      return dvRuntimeRefusal(runtime,
          because: 'pubspec.yaml sets dartvel.$runtime');
    }
  }
  return null;
}

/// A `dartvel:` section that configures a runtime, as plain data.
///
/// The section reaches the client, so it holds public metadata only: a key
/// that reads as a secret is refused here, whichever runtime the section is
/// for. The runtime validates what its own keys mean when it is installed.
Map<String, Object?> dvReadRuntimeSection(String name, Object? value) {
  if (value is! Map) {
    throw FormatException('dartvel.$name must be a map, not "$value"');
  }
  final Map<String, Object?> section = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final String key = '${entry.key}';
    if (RegExp(r'token|secret|password|private.?key|api.?key', caseSensitive: false).hasMatch(key)) {
      throw FormatException(
        'dartvel.$name.$key reads as a secret, and this section is sent to '
        'the client; keep secrets on the server (environment variables)',
      );
    }
    section[key] = _plain(entry.value);
  }
  return Map<String, Object?>.unmodifiable(section);
}

Object? _plain(Object? value) {
  if (value is Map) {
    return <String, Object?>{for (final MapEntry<Object?, Object?> e in value.entries) '${e.key}': _plain(e.value)};
  }
  if (value is List) return <Object?>[for (final Object? item in value) _plain(item)];
  return value;
}
