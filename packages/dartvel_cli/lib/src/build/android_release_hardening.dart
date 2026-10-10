/// What an Android release build is by default, written into the generated
/// Android project by `dartvel build` from `dartvel.android` in
/// `pubspec.yaml`.
///
/// Flutter's template is a starting point for a developer who will edit it,
/// and four of its defaults are wrong for an application nobody edits by
/// hand -- which, with `android/` generated at build time, is every Dartvel
/// application:
///
/// * `INTERNET` is declared only in the debug and profile manifests, so the
///   release build of an application with a backend cannot reach it.
/// * Release is signed with the debug key "so `flutter run --release`
///   works".
/// * Backup is on, so the session token and the offline data models leave
///   the device in a cloud backup and in every device-to-device transfer.
/// * Nothing keeps the Java Dartvel's Dart reaches by name over JNI, so R8
///   removes it from a minified release build.
///
/// Cleartext is the fifth: a release build refuses it everywhere except the
/// hosts `dartvel.android.cleartextHosts` lists.
///
/// Each file is generated, and each edit to a file Flutter generated is a
/// marked block or an attribute the next build writes again, so a second
/// build changes nothing and a changed pubspec changes exactly what it says.
library dartvel_cli.build.android_release_hardening;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/build_runner.dart' show readPubspecYaml;

/// `dartvel.android`'s release settings.
class DVAndroidReleaseConfig {
  const DVAndroidReleaseConfig({
    this.internet = true,
    this.allowBackup = false,
    this.cleartextHosts = const <String>[],
    this.signingKeyProperties,
  });

  /// Whether the main manifest declares `android.permission.INTERNET`.
  /// On unless the application says `internet: false`: an application with
  /// no network use is the exception, and one that needs it and lacks it
  /// fails only in release.
  final bool internet;

  /// Whether Android may back the application's data up. Off by default.
  final bool allowBackup;

  /// Hosts a release build may reach over cleartext HTTP. Empty by default.
  final List<String> cleartextHosts;

  /// The properties file holding the release key, relative to the project
  /// root, from `dartvel.android.signing.keyProperties`.
  final String? signingKeyProperties;

  /// [dartvelSection] (the pubspec's `dartvel:` map) read for its Android
  /// release settings. Throws a [FormatException] naming the setting when
  /// one has the wrong shape, rather than guessing what it meant.
  static DVAndroidReleaseConfig parse(Object? dartvelSection) {
    final Object? android =
        dartvelSection is Map ? dartvelSection['android'] : null;
    if (android == null) return const DVAndroidReleaseConfig();
    if (android is! Map) {
      throw const FormatException('dartvel.android must be a map.');
    }

    bool flag(String name, bool fallback) {
      final Object? value = android[name];
      if (value == null) return fallback;
      if (value is bool) return value;
      throw FormatException(
          'dartvel.android.$name must be true or false, not "$value".');
    }

    final Object? hostsValue = android['cleartextHosts'];
    final List<String> hosts = <String>[];
    if (hostsValue != null) {
      if (hostsValue is! List) {
        throw const FormatException(
            'dartvel.android.cleartextHosts must be a list of host names.');
      }
      for (final Object? entry in hostsValue) {
        final String host = '$entry'.trim();
        // A host name or an IP address and nothing else. A <domain> element
        // holding a scheme or a path matches no request, so the host stays
        // refused from a build that said it would allow it.
        if (!RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.\-]*[A-Za-z0-9])?$')
            .hasMatch(host)) {
          throw FormatException(
              'dartvel.android.cleartextHosts lists "$entry", which is not a '
              'host name. Write the host alone, as "api.example.test", with '
              'no scheme, port or path.');
        }
        if (!hosts.contains(host)) hosts.add(host);
      }
    }

    final Object? signing = android['signing'];
    String? keyProperties;
    if (signing != null) {
      if (signing is! Map) {
        throw const FormatException(
            'dartvel.android.signing must be a map, as '
            '`signing: {keyProperties: path/to/key.properties}`.');
      }
      final Object? path = signing['keyProperties'];
      if (path != null) {
        if (path is! String || path.trim().isEmpty) {
          throw const FormatException(
              'dartvel.android.signing.keyProperties must be a path.');
        }
        keyProperties = path.trim();
      }
    }

    return DVAndroidReleaseConfig(
      internet: flag('internet', true),
      allowBackup: flag('allowBackup', false),
      cleartextHosts: List<String>.unmodifiable(hosts),
      signingKeyProperties: keyProperties,
    );
  }
}

/// Where each generated file goes, relative to the project root.
const String dvAndroidNetworkSecurityConfigPath =
    'android/app/src/main/res/xml/dartvel_network_security_config.xml';
const String dvAndroidDebugNetworkSecurityConfigPath =
    'android/app/src/debug/res/xml/dartvel_network_security_config.xml';
const String dvAndroidProfileNetworkSecurityConfigPath =
    'android/app/src/profile/res/xml/dartvel_network_security_config.xml';
const String dvAndroidBackupRulesPath =
    'android/app/src/main/res/xml/dartvel_backup_rules.xml';
const String dvAndroidDataExtractionRulesPath =
    'android/app/src/main/res/xml/dartvel_data_extraction_rules.xml';
const String dvAndroidProguardRulesPath = 'android/app/proguard-rules.pro';

const String _markStart = '    <!-- dartvel.android.release: start -->\n';
const String _markEnd = '    <!-- dartvel.android.release: end -->\n';
const String _toolsNamespace =
    'xmlns:tools="http://schemas.android.com/tools"';

/// [manifest] (the main source set's) with INTERNET declared unless the
/// application opted out, and `<application>` carrying the backup and
/// network settings [config] decides.
String dvAndroidHardenedManifest(
    String manifest, DVAndroidReleaseConfig config) {
  String out = _replaceBlock(manifest, _markStart, _markEnd);

  // tools:replace below needs the namespace on the root element.
  if (!out.contains(_toolsNamespace)) {
    out = out.replaceFirst(
        '<manifest ', '<manifest $_toolsNamespace\n    ');
  }

  final Map<String, String> owned = <String, String>{
    'android:allowBackup': '${config.allowBackup}',
    // API 31 and later: allowBackup="false" does not stop a device-to-device
    // transfer, and only these rules do.
    'android:dataExtractionRules': '@xml/dartvel_data_extraction_rules',
    // API 30 and earlier.
    'android:fullBackupContent': '@xml/dartvel_backup_rules',
    // API 23, which reads no network security config.
    'android:usesCleartextTraffic': 'false',
    'android:networkSecurityConfig': '@xml/dartvel_network_security_config',
  };
  out = _withApplicationAttributes(out, owned);

  final bool declared = out.contains('android.permission.INTERNET');
  if (config.internet && !declared) {
    final int application = out.indexOf('<application');
    if (application >= 0) {
      final int lineStart = out.lastIndexOf('\n', application) + 1;
      final String block = '$_markStart'
          '    <!-- Flutter declares INTERNET only for debug and profile, so a\n'
          '         release build could not reach its own backend. Written\n'
          '         by dartvel build; dartvel.android.internet: false in\n'
          '         pubspec.yaml takes it out. -->\n'
          '    <uses-permission android:name="android.permission.INTERNET"/>\n'
          '$_markEnd';
      out = '${out.substring(0, lineStart)}$block${out.substring(lineStart)}';
    }
  }
  return out;
}

/// [manifest] with each of [owned] set on its `<application>` start tag,
/// replacing any value already there, and named in `tools:replace` so a
/// library manifest saying otherwise loses rather than failing the merge.
String _withApplicationAttributes(String manifest, Map<String, String> owned) {
  final int start = manifest.indexOf('<application');
  if (start < 0) return manifest;
  final int end = manifest.indexOf('>', start);
  if (end < 0) return manifest;
  String tag = manifest.substring(start, end);

  String? take(String name) {
    final RegExp attribute = RegExp('\\s+${RegExp.escape(name)}="([^"]*)"');
    final String? value = attribute.firstMatch(tag)?.group(1);
    tag = tag.replaceAll(attribute, '');
    return value;
  }

  final List<String> replaced = <String>[
    for (final String name in (take('tools:replace') ?? '').split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];
  for (final String name in owned.keys) {
    take(name);
    if (!replaced.contains(name)) replaced.add(name);
  }

  final StringBuffer added = StringBuffer();
  for (final MapEntry<String, String> entry in owned.entries) {
    added.write('\n        ${entry.key}="${entry.value}"');
  }
  added.write('\n        tools:replace="${replaced.join(',')}"');
  tag = '<application$added${tag.substring('<application'.length)}';
  return manifest.substring(0, start) + tag + manifest.substring(end);
}

String _replaceBlock(String source, String start, String end) {
  final int existing = source.indexOf(start);
  if (existing < 0) return source;
  final int stop = source.indexOf(end, existing);
  if (stop < 0) return source;
  return source.substring(0, existing) + source.substring(stop + end.length);
}

/// The hosts a debug or profile build may also reach over cleartext: the
/// device itself, and the machine running the emulator as Android's and
/// Genymotion's emulators address it.
const List<String> dvAndroidDevelopmentCleartextHosts = <String>[
  'localhost',
  '127.0.0.1',
  '10.0.2.2',
  '10.0.3.2',
];

/// The network security config: cleartext refused everywhere except
/// [hosts], plus [dvAndroidDevelopmentCleartextHosts] when [development].
String dvAndroidNetworkSecurityConfig(List<String> hosts,
    {required bool development}) {
  final List<String> allowed = <String>[
    ...hosts,
    if (development)
      for (final String host in dvAndroidDevelopmentCleartextHosts)
        if (!hosts.contains(host)) host,
  ];
  final StringBuffer out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- GENERATED by dartvel build from '
        'dartvel.android.cleartextHosts. Do not')
    ..writeln('     edit: the next build writes it again. -->')
    ..writeln('<network-security-config>')
    ..writeln('    <base-config cleartextTrafficPermitted="false">')
    ..writeln('        <trust-anchors>')
    ..writeln('            <certificates src="system"/>')
    ..writeln('        </trust-anchors>')
    ..writeln('    </base-config>');
  if (allowed.isNotEmpty) {
    out.writeln('    <domain-config cleartextTrafficPermitted="true">');
    for (final String host in allowed) {
      out.writeln('        <domain includeSubdomains="false">$host</domain>');
    }
    out.writeln('    </domain-config>');
  }
  out.writeln('</network-security-config>');
  return out.toString();
}

const List<String> _backupDomains = <String>[
  'root',
  'file',
  'database',
  'sharedpref',
  'external',
];

/// What never leaves the device even when backup is allowed: the databases,
/// and the device runtime's state (the sealed session token) and the
/// offline data models, which live under the files directory.
const List<(String, String)> _privateData = <(String, String)>[
  ('database', '.'),
  ('file', 'dartvel-device/'),
  ('file', 'dartvel-offline/'),
];

List<String> _excludes(bool allowBackup, String indent) => <String>[
      if (allowBackup)
        for (final (String domain, String path) in _privateData)
          '$indent<exclude domain="$domain" path="$path"/>'
      else
        for (final String domain in _backupDomains)
          '$indent<exclude domain="$domain" path="."/>',
    ];

/// The API 31+ data extraction rules: everything excluded when backup is
/// off, the private data excluded when it is on.
String dvAndroidDataExtractionRules({required bool allowBackup}) {
  final StringBuffer out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- GENERATED by dartvel build from dartvel.android.allowBackup. '
        'Do not')
    ..writeln('     edit: the next build writes it again. -->')
    ..writeln('<data-extraction-rules>');
  for (final String section in <String>['cloud-backup', 'device-transfer']) {
    out.writeln('    <$section>');
    for (final String line in _excludes(allowBackup, '        ')) {
      out.writeln(line);
    }
    out.writeln('    </$section>');
  }
  out.writeln('</data-extraction-rules>');
  return out.toString();
}

/// The API 30 and earlier full-backup rules, the same exclusions.
String dvAndroidBackupRules({required bool allowBackup}) {
  final StringBuffer out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- GENERATED by dartvel build from dartvel.android.allowBackup. '
        'Do not')
    ..writeln('     edit: the next build writes it again. -->')
    ..writeln('<full-backup-content>');
  for (final String line in _excludes(allowBackup, '    ')) {
    out.writeln(line);
  }
  out.writeln('</full-backup-content>');
  return out.toString();
}

const String _rulesStart = '# dartvel: start\n';
const String _rulesEnd = '# dartvel: end\n';

/// [existing] (the app module's `proguard-rules.pro`, or empty) with the
/// rules that keep what Dart reaches by name.
///
/// Flutter's Gradle plugin adds this file to the release build's R8 rules
/// whenever it exists. Nothing in Java refers to the bridges -- Dart finds
/// them with FindClass at run time -- so without a rule R8 removes or
/// renames them and the first call is a ClassNotFoundException on a device.
String dvAndroidProguardRules(String existing) {
  final String stripped = _replaceBlock(existing, _rulesStart, _rulesEnd);
  final String separator =
      stripped.isEmpty || stripped.endsWith('\n') ? '' : '\n';
  return '$stripped$separator'
      '$_rulesStart'
      '# Written by dartvel build. The classes Dartvel\'s Dart code looks up by\n'
      '# name over JNI -- the Context provider, the activity and capture\n'
      '# bridges, the billing bridge, the home widget publisher -- and every\n'
      '# member of them, since Dart calls them by name and signature.\n'
      '-keep class dev.dartvel.** { *; }\n'
      '$_rulesEnd';
}

/// The environment `dartvel build` hands Gradle the release key in, in
/// order: keystore path, keystore password, key alias, key password.
const List<String> dvAndroidSigningEnvironment = <String>[
  'DARTVEL_ANDROID_KEYSTORE',
  'DARTVEL_ANDROID_KEYSTORE_PASSWORD',
  'DARTVEL_ANDROID_KEY_ALIAS',
  'DARTVEL_ANDROID_KEY_PASSWORD',
];

const String _gradleStart = '// dartvel.android.signing: start';
const String _gradleEnd = '// dartvel.android.signing: end';

const String _refusal =
    'No release key: set dartvel.android.signing.keyProperties in pubspec.yaml '
    'or the DARTVEL_ANDROID_KEYSTORE, DARTVEL_ANDROID_KEYSTORE_PASSWORD and '
    'DARTVEL_ANDROID_KEY_ALIAS variables, and '
    'build with dartvel build android. Dartvel does not sign a release with '
    'the debug key.';

/// [gradle] (the app module's build script) signing release with the key in
/// [dvAndroidSigningEnvironment], and failing a release build Gradle is
/// asked for without one rather than falling back to the debug key.
///
/// A block of its own after the template's, so its assignment is the one
/// that stands. It names the variables, never their values: the key and its
/// passwords stay where the developer keeps them.
String dvAndroidGradleWithSigning(String gradle, {required bool kotlinScript}) {
  final String stripped = _stripGradle(gradle);
  final String separator = stripped.endsWith('\n') ? '' : '\n';
  final String body = kotlinScript
      ? '''
val dartvelKeystore: String? = System.getenv("${dvAndroidSigningEnvironment[0]}")
android {
    signingConfigs {
        create("dartvelRelease") {
            if (dartvelKeystore != null) {
                storeFile = file(dartvelKeystore)
                storePassword = System.getenv("${dvAndroidSigningEnvironment[1]}")
                keyAlias = System.getenv("${dvAndroidSigningEnvironment[2]}")
                keyPassword = System.getenv("${dvAndroidSigningEnvironment[3]}")
                    ?: System.getenv("${dvAndroidSigningEnvironment[1]}")
            }
        }
    }
    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("dartvelRelease")
        }
    }
}
tasks.configureEach {
    if (dartvelKeystore == null && name == "preReleaseBuild") {
        doFirst {
            throw GradleException("$_refusal")
        }
    }
}
'''
      : '''
def dartvelKeystore = System.getenv('${dvAndroidSigningEnvironment[0]}')
android {
    signingConfigs {
        create('dartvelRelease') {
            if (dartvelKeystore != null) {
                storeFile file(dartvelKeystore)
                storePassword System.getenv('${dvAndroidSigningEnvironment[1]}')
                keyAlias System.getenv('${dvAndroidSigningEnvironment[2]}')
                keyPassword System.getenv('${dvAndroidSigningEnvironment[3]}') ?: System.getenv('${dvAndroidSigningEnvironment[1]}')
            }
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.getByName('dartvelRelease')
        }
    }
}
tasks.configureEach { task ->
    if (dartvelKeystore == null && task.name == 'preReleaseBuild') {
        task.doFirst {
            throw new GradleException('$_refusal')
        }
    }
}
''';
  return '$stripped$separator'
      '\n$_gradleStart\n'
      '// Release signing, written by dartvel build from dartvel.android.signing\n'
      '// in pubspec.yaml. The key and its passwords come from the environment\n'
      '// dartvel build hands Gradle and are never written here; a release\n'
      '// build with no key fails instead of falling back to the debug key.\n'
      '$body'
      '$_gradleEnd\n';
}

String _stripGradle(String gradle) {
  final int start = gradle.indexOf(_gradleStart);
  if (start < 0) return gradle;
  final int end = gradle.indexOf(_gradleEnd, start);
  if (end < 0) return gradle;
  int cut = start;
  if (cut >= 2 && gradle.substring(cut - 2, cut) == '\n\n') cut -= 1;
  int after = end + _gradleEnd.length;
  if (after < gradle.length && gradle[after] == '\n') after += 1;
  return gradle.substring(0, cut) + gradle.substring(after);
}

/// A release key, as the environment Gradle reads it from.
class DVAndroidSigning {
  const DVAndroidSigning({
    required this.storeFile,
    required this.storePassword,
    required this.keyAlias,
    required this.keyPassword,
    required this.source,
  });

  /// The keystore's absolute path.
  final String storeFile;
  final String storePassword;
  final String keyAlias;
  final String keyPassword;

  /// Where it came from, for the build log. Never a secret.
  final String source;

  Map<String, String> get environment => <String, String>{
        dvAndroidSigningEnvironment[0]: storeFile,
        dvAndroidSigningEnvironment[1]: storePassword,
        dvAndroidSigningEnvironment[2]: keyAlias,
        dvAndroidSigningEnvironment[3]: keyPassword,
      };
}

/// The release key, or why there is none.
class DVAndroidSigningResolution {
  const DVAndroidSigningResolution.found(DVAndroidSigning this.signing)
      : problem = null;
  const DVAndroidSigningResolution.refused(String this.problem)
      : signing = null;

  final DVAndroidSigning? signing;
  final String? problem;
}

/// How to configure a release key, for the message a refusal ends with.
const String dvAndroidSigningHelp =
    'Configure a release key one of two ways, keeping it and its passwords '
    'out of the repository:\n'
    '  1. dartvel.android.signing.keyProperties in pubspec.yaml, naming a '
    'properties file (relative to the project) with storeFile (relative to '
    'that file), storePassword, keyAlias and, when it differs from the '
    'keystore\'s, keyPassword; or\n'
    '  2. the variables DARTVEL_ANDROID_KEYSTORE, '
    'DARTVEL_ANDROID_KEYSTORE_PASSWORD and DARTVEL_ANDROID_KEY_ALIAS (and '
    'DARTVEL_ANDROID_KEY_PASSWORD when it differs), as a CI secret store '
    'sets them.\n'
    'To make a key: keytool -genkeypair -v -keystore upload.jks -keyalg RSA '
    '-keysize 4096 -validity 10000 -alias upload';

/// The release key for the project at [root]: from the four
/// [dvAndroidSigningEnvironment] variables in [environment] when they are
/// set, else from the properties file `dartvel.android.signing` names, else
/// from `android/key.properties` (Flutter's own convention, `storeFile`
/// relative to `android/app`). Refused, with what to do, when there is none
/// or what there is cannot work.
DVAndroidSigningResolution dvResolveAndroidSigning({
  required String root,
  required DVAndroidReleaseConfig config,
  required Map<String, String> environment,
}) {
  // The key password is optional: without one the keystore's is used, as
  // keytool's PKCS12 keys have it.
  final List<String> required = dvAndroidSigningEnvironment.sublist(0, 3);
  final List<String> present = <String>[
    for (final String name in dvAndroidSigningEnvironment)
      if ((environment[name] ?? '').isNotEmpty) name,
  ];
  if (present.isNotEmpty) {
    final List<String> missing = <String>[
      for (final String name in required)
        if (!present.contains(name)) name,
    ];
    if (missing.isNotEmpty) {
      return DVAndroidSigningResolution.refused(
          'The release key is half configured: ${present.join(', ')} '
          '${present.length == 1 ? 'is' : 'are'} set and ${missing.join(', ')} '
          '${missing.length == 1 ? 'is' : 'are'} not.\n$dvAndroidSigningHelp');
    }
    final String store = p.isAbsolute(environment[dvAndroidSigningEnvironment[0]]!)
        ? environment[dvAndroidSigningEnvironment[0]]!
        : p.join(root, environment[dvAndroidSigningEnvironment[0]]!);
    return _checked(DVAndroidSigning(
      storeFile: p.normalize(store),
      storePassword: environment[dvAndroidSigningEnvironment[1]]!,
      keyAlias: environment[dvAndroidSigningEnvironment[2]]!,
      keyPassword: (environment[dvAndroidSigningEnvironment[3]] ?? '').isNotEmpty
          ? environment[dvAndroidSigningEnvironment[3]]!
          : environment[dvAndroidSigningEnvironment[1]]!,
      source: 'the DARTVEL_ANDROID_* variables',
    ));
  }

  final String? declared = config.signingKeyProperties;
  if (declared != null) {
    final String path = p.normalize(p.isAbsolute(declared) ? declared : p.join(root, declared));
    if (!File(path).existsSync()) {
      return DVAndroidSigningResolution.refused(
          'dartvel.android.signing.keyProperties names $declared, and there '
          'is no file at $path.\n$dvAndroidSigningHelp');
    }
    return _fromProperties(path,
        storeBase: p.dirname(path),
        source: 'dartvel.android.signing.keyProperties ($declared)');
  }

  final String flutterConvention = p.join(root, 'android', 'key.properties');
  if (File(flutterConvention).existsSync()) {
    return _fromProperties(flutterConvention,
        storeBase: p.join(root, 'android', 'app'),
        source: 'android/key.properties');
  }

  return const DVAndroidSigningResolution.refused(
      'A release build needs a release key, and none is configured. Dartvel '
      'will not sign a release with the debug key: Google Play refuses it, '
      'and anything else that installs it gets an application whose updates '
      'anybody with the Android SDK can sign.\n$dvAndroidSigningHelp');
}

DVAndroidSigningResolution _fromProperties(String path,
    {required String storeBase, required String source}) {
  final Map<String, String> values = <String, String>{};
  for (final String line in File(path).readAsLinesSync()) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || !trimmed.contains('=')) {
      continue;
    }
    final int equals = trimmed.indexOf('=');
    values[trimmed.substring(0, equals).trim()] =
        trimmed.substring(equals + 1).trim();
  }
  final List<String> missing = <String>[
    for (final String key in const <String>[
      'storeFile',
      'storePassword',
      'keyAlias',
    ])
      if ((values[key] ?? '').isEmpty) key,
  ];
  if (missing.isNotEmpty) {
    return DVAndroidSigningResolution.refused(
        '$path has no ${missing.join(', ')}, so it cannot sign a release.\n'
        '$dvAndroidSigningHelp');
  }
  final String store = values['storeFile']!;
  return _checked(DVAndroidSigning(
    storeFile: p.normalize(p.isAbsolute(store) ? store : p.join(storeBase, store)),
    storePassword: values['storePassword']!,
    keyAlias: values['keyAlias']!,
    keyPassword: (values['keyPassword'] ?? '').isNotEmpty
        ? values['keyPassword']!
        : values['storePassword']!,
    source: source,
  ));
}

DVAndroidSigningResolution _checked(DVAndroidSigning signing) {
  if (!File(signing.storeFile).existsSync()) {
    return DVAndroidSigningResolution.refused(
        'The release key is configured from ${signing.source}, and there is '
        'no keystore at ${signing.storeFile}.\n$dvAndroidSigningHelp');
  }
  return DVAndroidSigningResolution.found(signing);
}

/// The release key for the project at [root] as the environment Gradle
/// reads it from, or empty when none resolves -- for the other commands that
/// run a release Gradle build on the generated project (`dartvel updates`),
/// which then meet the Gradle block's own refusal rather than the debug key.
Map<String, String> dvAndroidSigningEnvironmentFor(
    String root, Map<String, String> environment) {
  try {
    return dvResolveAndroidSigning(
          root: root,
          config: DVAndroidReleaseConfig.parse(readPubspecYaml(root)?['dartvel']),
          environment: environment,
        ).signing?.environment ??
        const <String, String>{};
  } on FormatException {
    return const <String, String>{};
  }
}
