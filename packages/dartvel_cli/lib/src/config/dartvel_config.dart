import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../utils/helpers.dart';

class DartvelConfig {
  final String packageName;
  final String pagesDir;
  final String modelsDir;
  final String backendDir;
  final String componentsDir;
  final String stylesDir;
  final String servicesDir;
  final String backendHost;
  final int backendPort;
  final String devBackendHost;
  final String prodBackendHost;
  final String apiBasePath;
  final List<String> envFiles;
  final DartvelSeoConfig seo;
  final DartvelTransitionConfig transitions;
  final bool normalizeTrailingSlash;
  final String notFoundRedirect;
  final List<String> plugins;
  final bool webPrerender;
  final bool ota;
  final YamlMap raw;
  final DartvelDartConfigReference? dartConfigReference;

  const DartvelConfig({
    required this.packageName,
    required this.pagesDir,
    required this.modelsDir,
    required this.backendDir,
    required this.componentsDir,
    required this.stylesDir,
    required this.servicesDir,
    required this.backendHost,
    required this.backendPort,
    required this.devBackendHost,
    required this.prodBackendHost,
    required this.apiBasePath,
    required this.envFiles,
    required this.seo,
    required this.transitions,
    required this.normalizeTrailingSlash,
    required this.notFoundRedirect,
    required this.plugins,
    required this.webPrerender,
    required this.ota,
    required this.raw,
    this.dartConfigReference,
  });

  static Future<DartvelConfig> load(Directory root) async {
    final pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw FileSystemException('pubspec.yaml not found', pubspec.path);
    }
    final yaml = loadYaml(await pubspec.readAsString());
    if (yaml is! YamlMap) {
      throw const FormatException('pubspec.yaml must contain a YAML map.');
    }
    final packageName = (yaml['name'] ?? 'app').toString();
    final dartvel = yaml['dartvel'];
    final DartvelDartConfigReference? dartConfigReference;
    final YamlMap raw;
    if (dartvel is String) {
      dartConfigReference = DartvelDartConfigReference.validate(
        root: root,
        relativePath: dartvel,
      );
      raw = YamlMap.wrap(<String, Object?>{});
    } else {
      dartConfigReference = null;
      raw = dartvel is YamlMap ? dartvel : YamlMap.wrap(<String, Object?>{});
    }

    final backendPort = asInt(raw['backendPort'], 3000);
    final seo = _map(raw['seo']) ?? _map(raw['webSeoDefaults']);
    final transitions = _map(raw['webTransitions']) ?? _map(raw['transitions']);
    return DartvelConfig(
      packageName: packageName,
      pagesDir: _string(raw['pagesDir'], 'lib/pages'),
      modelsDir: _string(raw['modelsDir'], 'lib/models'),
      backendDir: _string(raw['backendDir'], 'lib/backend'),
      componentsDir: _string(raw['componentsDir'], 'lib/components'),
      stylesDir: _string(raw['stylesDir'], 'lib/styles'),
      servicesDir: _string(raw['servicesDir'], 'lib/services'),
      backendHost: _string(raw['backendHost'], '0.0.0.0'),
      backendPort: backendPort,
      devBackendHost:
          _string(raw['devBackendHost'], 'http://localhost:$backendPort'),
      prodBackendHost: _string(raw['prodBackendHost'], ''),
      apiBasePath: _string(raw['apiBasePath'], '/api'),
      envFiles: _stringList(raw['envFiles'], const <String>[
        '.env',
        '.env.local',
      ]),
      seo: DartvelSeoConfig(
        siteName: _string(seo?['siteName'], ''),
        title: _string(seo?['defaultTitle'] ?? seo?['title'], ''),
        description:
            _string(seo?['defaultDescription'] ?? seo?['description'], ''),
        image: _string(seo?['defaultImage'] ?? seo?['image'], ''),
        twitterHandle: _string(seo?['twitterHandle'], ''),
      ),
      transitions: DartvelTransitionConfig(
        defaultTransition: _string(transitions?['default'], 'fade'),
        durationMs: asInt(transitions?['durationMs'], 220),
        curve: _string(transitions?['curve'], 'easeInOut'),
      ),
      normalizeTrailingSlash:
          asBool(raw['routingNormalizeTrailingSlash'], true),
      notFoundRedirect: _string(raw['notFoundRedirect'], ''),
      plugins: _stringList(raw['plugins'], const <String>[]),
      webPrerender: asBool(raw['webPrerender'], false),
      ota: asBool(raw['ota'], false),
      raw: raw,
      dartConfigReference: dartConfigReference,
    );
  }

  static String _string(Object? value, String fallback) =>
      value == null ? fallback : value.toString();

  static YamlMap? _map(Object? value) => value is YamlMap ? value : null;

  static List<String> _stringList(Object? value, List<String> fallback) {
    if (value is! YamlList) return List<String>.unmodifiable(fallback);
    return List<String>.unmodifiable(
      value.where((item) => item != null).map((item) => item.toString()),
    );
  }
}

class DartvelSeoConfig {
  final String siteName;
  final String title;
  final String description;
  final String image;
  final String twitterHandle;

  const DartvelSeoConfig({
    required this.siteName,
    required this.title,
    required this.description,
    required this.image,
    required this.twitterHandle,
  });
}

class DartvelTransitionConfig {
  final String defaultTransition;
  final int durationMs;
  final String curve;

  const DartvelTransitionConfig({
    required this.defaultTransition,
    required this.durationMs,
    required this.curve,
  });
}

class DartvelDartConfigReference {
  final String relativePath;
  final String className;

  const DartvelDartConfigReference({
    required this.relativePath,
    required this.className,
  });

  static DartvelDartConfigReference validate({
    required Directory root,
    required String relativePath,
  }) {
    final file = File(p.join(root.path, relativePath));
    if (!file.existsSync()) {
      throw FileSystemException(
        'Dartvel Dart config file not found',
        file.path,
      );
    }
    final content = file.readAsStringSync();
    final match = RegExp(
      r'class\s+([A-Z][A-Za-z0-9_]*)\s+extends\s+DartvelConfig\b',
    ).firstMatch(content);
    if (match == null) {
      throw FormatException(
        'Dartvel Dart config must expose a public class extending DartvelConfig: ${file.path}',
      );
    }
    return DartvelDartConfigReference(
      relativePath: relativePath,
      className: match.group(1)!,
    );
  }
}
