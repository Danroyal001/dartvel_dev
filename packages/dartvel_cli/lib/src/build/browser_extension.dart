import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The browsers Dartvel can package a Flutter web build for.
///
/// The two differ in ways that are not cosmetic: Chromium runs a manifest V3
/// service worker, Firefox runs an event page and refuses to load a manifest
/// that declares `service_worker`.
enum BrowserExtensionTarget {
  chromium('Chromium'),
  firefox('Firefox');

  const BrowserExtensionTarget(this.label);

  /// Name used in build output.
  final String label;

  /// Maps a `dartvel build` platform onto a target.
  ///
  /// Returns null for anything that is not a browser extension platform, so
  /// the caller reports an unknown target rather than silently packaging one.
  static BrowserExtensionTarget? forTarget(String platform) =>
      switch (platform) {
        'chrome-extension' => chromium,
        'firefox-extension' => firefox,
        _ => null,
      };
}

/// What the generated manifest says about the extension.
///
/// Defaults come from the package itself so an application that declares
/// nothing still builds; `dartvel.extension` in `pubspec.yaml` overrides them.
class BrowserExtensionConfig {
  const BrowserExtensionConfig({
    required this.name,
    required this.version,
    this.description,
    this.permissions = const <String>[],
    this.hostPermissions = const <String>[],
    this.geckoId,
    this.usePopup = true,
  });

  final String name;
  final String version;
  final String? description;
  final List<String> permissions;
  final List<String> hostPermissions;

  /// Firefox requires a stable extension id; Chromium derives its own.
  final String? geckoId;

  /// Whether clicking the toolbar icon opens the app in a popup. When false
  /// the app opens in a tab instead, driven by the background script.
  final bool usePopup;

  static BrowserExtensionConfig fromPubspec(YamlMap pubspec) {
    final dartvel = pubspec['dartvel'];
    final overrides = dartvel is YamlMap && dartvel['extension'] is YamlMap
        ? dartvel['extension'] as YamlMap
        : null;

    String? inherited(String key) {
      final value = overrides?[key] ?? pubspec[key];
      return value == null ? null : '$value';
    }

    List<String> declared(String key) {
      final value = overrides?[key];
      if (value is! YamlList) return const <String>[];
      return value.map((Object? entry) => '$entry').toList(growable: false);
    }

    final popup = overrides?['popup'];

    return BrowserExtensionConfig(
      name: inherited('name') ?? 'Dartvel App',
      version: inherited('version') ?? '1.0.0',
      description: inherited('description'),
      permissions: declared('permissions'),
      hostPermissions: declared('hostPermissions'),
      geckoId: overrides?['geckoId'] == null
          ? null
          : '${overrides!['geckoId']}',
      usePopup: popup is bool ? popup : true,
    );
  }
}

/// Whether the assembled bundle is actually loadable, and what it lacks.
class BrowserExtensionArtifacts {
  const BrowserExtensionArtifacts(this.missing);

  /// Required files that are absent, named as the browser would look for them.
  final List<String> missing;

  bool get isValid => missing.isEmpty;
}

/// Files without which a browser refuses to load the unpacked extension.
const _requiredArtifacts = <String>[
  'index.html',
  'main.dart.js',
  'manifest.json',
  'background.js',
];

/// Flutter's own service worker fights the extension's over fetch handling, so
/// it is dropped rather than shipped.
const _excludedFromBundle = <String>{'flutter_service_worker.js'};

const _fallbackVersion = '1.0.0';

/// Coerces a pub version into one a browser will accept.
///
/// Extension stores take one to four dot-separated integers and reject
/// anything else outright, so `1.2.0+3` and `1.2.0-beta.1` — both ordinary pub
/// versions — produce an extension that cannot be loaded if passed through.
String normalizeExtensionVersion(String version) {
  final base = version.split(RegExp('[+-]')).first.trim();
  final parts =
      base.split('.').where((String part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return _fallbackVersion;

  final numeric = <String>[];
  for (final part in parts.take(4)) {
    final value = int.tryParse(part);
    if (value == null || value < 0) return _fallbackVersion;
    numeric.add('$value');
  }
  return numeric.join('.');
}

/// Builds the manifest V3 document for [target].
Map<String, Object?> buildExtensionManifest(
  BrowserExtensionConfig config,
  BrowserExtensionTarget target,
) {
  return <String, Object?>{
    'manifest_version': 3,
    'name': config.name,
    'version': normalizeExtensionVersion(config.version),
    if (config.description != null) 'description': config.description,
    'background': switch (target) {
      BrowserExtensionTarget.chromium => <String, Object?>{
          'service_worker': 'background.js',
          'type': 'module',
        },
      BrowserExtensionTarget.firefox => <String, Object?>{
          'scripts': <String>['background.js'],
        },
    },
    // No `unsafe-eval` and no `unsafe-inline`: manifest V3 forbids both, which
    // is why the web build is made with `--csp`.
    'content_security_policy': <String, Object?>{
      'extension_pages': "script-src 'self'; object-src 'self'",
    },
    if (config.permissions.isNotEmpty) 'permissions': config.permissions,
    if (config.hostPermissions.isNotEmpty)
      'host_permissions': config.hostPermissions,
    if (config.usePopup)
      'action': <String, Object?>{'default_popup': 'index.html'},
    if (target == BrowserExtensionTarget.firefox && config.geckoId != null)
      'browser_specific_settings': <String, Object?>{
        'gecko': <String, Object?>{'id': config.geckoId},
      },
  };
}

/// Builds the background script the manifest points at.
///
/// Chromium exposes the extension API as `chrome` and Firefox as `browser`, so
/// the script resolves whichever exists rather than being generated per target.
String buildBackgroundScript(BrowserExtensionConfig config) {
  final script = StringBuffer()
    ..writeln('// Generated by Dartvel. Do not edit.')
    ..writeln('const api = globalThis.browser ?? globalThis.chrome;');

  if (!config.usePopup) {
    // Without a popup there is no toolbar surface to render into, so the app
    // is opened as a full tab instead. `onInstalled` is the listener that
    // still fires when the manifest declares no action.
    script
      ..writeln('')
      ..writeln('function openApp() {')
      ..writeln("  api.tabs.create({url: api.runtime.getURL('index.html')});")
      ..writeln('}')
      ..writeln('')
      ..writeln('api.runtime.onInstalled.addListener(openApp);')
      ..writeln('api.action?.onClicked?.addListener(openApp);');
  }

  return script.toString();
}

/// Copies the Flutter web build into [outputDir] and writes the extension
/// files beside it.
///
/// Throws [FileSystemException] when there is no web build to package.
void assembleExtensionBundle({
  required String webBuildDir,
  required String outputDir,
  required BrowserExtensionConfig config,
  required BrowserExtensionTarget target,
}) {
  final source = Directory(webBuildDir);
  if (!source.existsSync()) {
    throw FileSystemException('No Flutter web build to package', webBuildDir);
  }

  // Wiped rather than merged: a file left by the previous build is still
  // loaded by the browser, so a rebuild that only adds files ships stale code.
  final destination = Directory(outputDir);
  if (destination.existsSync()) destination.deleteSync(recursive: true);
  destination.createSync(recursive: true);

  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    if (_excludedFromBundle.contains(p.basename(relative))) continue;

    final copy = p.join(outputDir, relative);
    if (entity is Directory) {
      Directory(copy).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(copy)).createSync(recursive: true);
      entity.copySync(copy);
    }
  }

  const encoder = JsonEncoder.withIndent('  ');
  File(p.join(outputDir, 'manifest.json')).writeAsStringSync(
    '${encoder.convert(buildExtensionManifest(config, target))}\n',
  );
  File(p.join(outputDir, 'background.js'))
      .writeAsStringSync(buildBackgroundScript(config));
}

/// Reports which required files [outputDir] is missing.
BrowserExtensionArtifacts validateExtensionArtifacts(String outputDir) {
  return BrowserExtensionArtifacts(<String>[
    for (final name in _requiredArtifacts)
      if (!File(p.join(outputDir, name)).existsSync()) name,
  ]);
}
