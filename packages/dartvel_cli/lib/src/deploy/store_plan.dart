/// Publishing an application to a store, as a plan that is checked first.
///
/// The specification asks Dartvel to handle publishing and distribution for
/// every platform. `dartvel deploy` covers a web host and a server; an
/// application going to Google Play, App Store Connect or a tester group was
/// a set of commands somebody kept in their head.
///
/// The failures worth guarding are the ones that waste an upload rather than
/// the ones that crash. A publish that starts, spends four minutes on a
/// binary and then asks for a credential nobody gave it has failed after
/// doing the expensive part; a publish to the wrong track has succeeded at
/// the wrong thing. So the plan is resolved and validated before anything
/// runs, and every refusal names the line of pubspec.yaml that would fix it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The stores `dartvel deploy --store` takes, each declared under
/// `dartvel.deploy.stores.<store>` in pubspec.yaml.
///
/// Firebase is spelled out because it is also a host, reached through
/// `--provider firebase-hosting`; a bare `firebase` names neither.
const List<String> dvStores = <String>[
  'play',
  'appstore',
  'testflight',
  'firebase-app-distribution',
];

/// The tracks Google Play publishes to.
const List<String> dvPlayTracks = <String>[
  'internal',
  'alpha',
  'beta',
  'production',
];

class DVStorePlan {
  const DVStorePlan({
    required this.store,
    required this.executable,
    required this.arguments,
    required this.artifact,
    required this.toolchain,
    this.problems = const <String>[],
  });

  /// A plan that cannot run, and why.
  const DVStorePlan.refused(this.store, this.problems)
    : executable = '',
      arguments = const <String>[],
      artifact = '',
      toolchain = '';

  final String store;
  final String executable;
  final List<String> arguments;

  /// The file that is uploaded.
  final String artifact;

  /// What has to be on PATH. Named so the build can check it before it
  /// builds rather than after: a plan whose executable nobody has is a build
  /// that finishes and then cannot deliver.
  final String toolchain;

  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// The plan for [store], read from the project at [root].
///
/// [host] is `linux`, `macos` or `windows`; passed rather than read so the
/// decision can be tested from any machine, which is the whole difficulty
/// with anything Apple.
DVStorePlan dvStorePlan({
  required String store,
  required String root,
  required String host,
  Map<String, String> environment = const <String, String>{},
}) {
  if (!dvStores.contains(store)) {
    return DVStorePlan.refused(store, <String>[
      '"$store" is not a store Dartvel deploys to. The ones it knows are '
          '${dvStores.join(', ')}.',
    ]);
  }

  final String? moved = _oldDeclaration(root, store);
  if (moved != null) return DVStorePlan.refused(store, <String>[moved]);

  final Map<Object?, Object?> declared = _declaration(root, store);
  if (declared.isEmpty) {
    return DVStorePlan.refused(store, <String>[
      'This project declares nothing under dartvel.deploy.stores.$store in '
          'pubspec.yaml, so there is nowhere to deploy to and nothing to '
          'deploy with.',
    ]);
  }

  switch (store) {
    case 'play':
      return _play(root, declared, environment['DARTVEL_PLAY_SERVICE_ACCOUNT']);
    case 'appstore':
    case 'testflight':
      return _appStore(store, root, declared, host);
    default:
      return _firebase(root, declared);
  }
}

DVStorePlan _play(
  String root,
  Map<Object?, Object?> declared,
  String? keyFile,
) {
  final List<String> problems = <String>[];
  final String track = '${declared['track'] ?? 'internal'}';
  if (!dvPlayTracks.contains(track)) {
    // Not corrected to the nearest: "staging" could mean internal or alpha,
    // and guessing puts a build in front of the wrong people.
    problems.add(
      'dartvel.deploy.stores.play.track is "$track". Google Play '
      'publishes to ${dvPlayTracks.join(', ')}.',
    );
  }
  final bool fromEnvironment = keyFile != null && keyFile.trim().isNotEmpty;
  final Object? credentials = fromEnvironment
      ? keyFile
      : declared['credentials'];
  if (credentials == null || '$credentials'.trim().isEmpty) {
    // Without it fastlane prompts, and a pipeline with no terminal waits for
    // an answer until the job's cap.
    problems.add(
      'dartvel.deploy.stores.play.credentials names no service account '
      'key. Add it to pubspec.yaml: without one the upload stops to ask, '
      'and a pipeline has nobody to answer.',
    );
  }

  // The bundle, not the APK. Play has taken app bundles for years and an APK
  // is refused at the end of the upload rather than the start.
  final String artifact = p.join(
    root,
    'build',
    'app',
    'outputs',
    'bundle',
    'release',
    'app-release.aab',
  );
  if (problems.isNotEmpty) return DVStorePlan.refused('play', problems);
  return DVStorePlan(
    store: 'play',
    executable: 'fastlane',
    arguments: <String>[
      'supply',
      '--aab',
      artifact,
      '--track',
      track,
      '--json_key',
      // A Dartvel Cloud worker names the key it was given by path; a project
      // names its own relative to itself.
      fromEnvironment ? keyFile : p.join(root, '$credentials'),
      // Uploaded and left alone. A publish that also promoted the build would
      // do two things under one word, and the second is somebody's decision.
      '--skip_upload_metadata',
      '--skip_upload_images',
      '--skip_upload_screenshots',
    ],
    artifact: artifact,
    toolchain: 'fastlane',
  );
}

DVStorePlan _appStore(
  String store,
  String root,
  Map<Object?, Object?> declared,
  String host,
) {
  final List<String> problems = <String>[];
  if (host != 'macos') {
    // Apple's upload tools are part of Xcode. A plan that pretended otherwise
    // would fail at the end of a long build with "command not found", which
    // reads as a broken installation rather than as the wrong machine.
    problems.add(
      'Publishing to $store needs Xcode, so it runs on macOS. '
      'This is $host.',
    );
  }
  final Object? key = declared['apiKey'];
  final Object? issuer = declared['apiIssuer'];
  if (key == null || '$key'.trim().isEmpty) {
    problems.add(
      'dartvel.deploy.stores.$store.apiKey names no App Store Connect '
      'API key.',
    );
  }
  if (issuer == null || '$issuer'.trim().isEmpty) {
    problems.add(
      'dartvel.deploy.stores.$store.apiIssuer names no issuer id. The '
      'key alone does not say which account it belongs to.',
    );
  }
  if (problems.isNotEmpty) return DVStorePlan.refused(store, problems);

  // flutter build ipa names the file after the app, so it is found rather
  // than assumed; app.ipa is what a refusal names when nothing was built.
  final Directory ipas = Directory(p.join(root, 'build', 'ios', 'ipa'));
  final List<String> built = ipas.existsSync()
      ? (ipas
            .listSync()
            .whereType<File>()
            .map((File f) => f.path)
            .where((String f) => f.endsWith('.ipa'))
            .toList()
          ..sort())
      : const <String>[];
  final String artifact = built.isNotEmpty
      ? built.first
      : p.join(ipas.path, 'app.ipa');
  return DVStorePlan(
    store: store,
    executable: 'xcrun',
    arguments: <String>[
      'altool',
      '--upload-app',
      '-f',
      artifact,
      '-t',
      'ios',
      '--apiKey',
      '$key',
      '--apiIssuer',
      '$issuer',
    ],
    artifact: artifact,
    toolchain: 'xcrun',
  );
}

DVStorePlan _firebase(String root, Map<Object?, Object?> declared) {
  final List<String> problems = <String>[];
  final Object? app = declared['app'];
  if (app == null || '$app'.trim().isEmpty) {
    problems.add(
      'dartvel.deploy.stores.firebase-app-distribution.app names no '
      'application id. '
      'App Distribution identifies a build by it, and there is no way to '
      'guess which of an account\'s applications this is.',
    );
  }
  if (problems.isNotEmpty) {
    return DVStorePlan.refused('firebase-app-distribution', problems);
  }

  final Object? groups = declared['groups'];
  final List<String> testers = <String>[
    if (groups is List)
      for (final Object? group in groups) '$group'
    else if (groups != null)
      '$groups',
  ];
  final String artifact = p.join(
    root,
    'build',
    'app',
    'outputs',
    'flutter-apk',
    'app-release.apk',
  );
  return DVStorePlan(
    store: 'firebase-app-distribution',
    executable: 'firebase',
    arguments: <String>[
      'appdistribution:distribute',
      artifact,
      '--app',
      '$app',
      if (testers.isNotEmpty) ...<String>['--groups', testers.join(',')],
    ],
    artifact: artifact,
    toolchain: 'firebase',
  );
}

Map<Object?, Object?> _declaration(String root, String store) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return const <Object?, Object?>{};
  try {
    final Object? document = loadYaml(pubspec.readAsStringSync());
    final Object? dartvel = document is Map ? document['dartvel'] : null;
    final Object? deploy = dartvel is Map ? dartvel['deploy'] : null;
    final Object? stores = deploy is Map ? deploy['stores'] : null;
    final Object? declared = stores is Map ? stores[store] : null;
    return declared is Map ? declared : const <Object?, Object?>{};
  } catch (_) {
    // A pubspec that will not parse is the build's own message to give.
    return const <Object?, Object?>{};
  }
}

/// Why the project's pubspec.yaml still has a `dartvel.publish` block, or
/// null when it has none.
///
/// Refused rather than read: store declarations are deploy configuration,
/// and a key that is quietly honoured is one the documentation stops naming
/// while projects go on depending on it. Refused rather than ignored: a
/// store declared the old way would otherwise read as not declared at all.
String? _oldDeclaration(String root, String store) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  try {
    final Object? document = loadYaml(pubspec.readAsStringSync());
    final Object? dartvel = document is Map ? document['dartvel'] : null;
    if (dartvel is! Map || !dartvel.containsKey('publish')) return null;
    final Object? old = dartvel['publish'];
    final List<String> moves = <String>[
      if (old is Map)
        for (final Object? key in old.keys)
          'dartvel.publish.$key is now dartvel.deploy.stores.'
              '${key == 'firebase' ? 'firebase-app-distribution' : key}',
    ];
    return 'pubspec.yaml declares dartvel.publish, which Dartvel no longer '
        'reads: store declarations are under dartvel.deploy.stores. '
        '${moves.isEmpty ? 'Declare this store as dartvel.deploy.stores.$store.' : '${moves.join('; ')}.'}';
  } catch (_) {
    return null;
  }
}
