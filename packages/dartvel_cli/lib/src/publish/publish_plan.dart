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

/// The stores `dartvel publish` knows.
const List<String> dvPublishStores = <String>[
  'play',
  'appstore',
  'testflight',
  'firebase',
];

/// The tracks Google Play publishes to.
const List<String> dvPlayTracks = <String>[
  'internal',
  'alpha',
  'beta',
  'production',
];

class DVPublishPlan {
  const DVPublishPlan({
    required this.store,
    required this.executable,
    required this.arguments,
    required this.artifact,
    required this.toolchain,
    this.problems = const <String>[],
  });

  /// A plan that cannot run, and why.
  const DVPublishPlan.refused(this.store, this.problems)
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
DVPublishPlan dvPublishPlan({
  required String store,
  required String root,
  required String host,
}) {
  if (!dvPublishStores.contains(store)) {
    return DVPublishPlan.refused(store, <String>[
      '"$store" is not a store Dartvel publishes to. The ones it knows are '
          '${dvPublishStores.join(', ')}.',
    ]);
  }

  final Map<Object?, Object?> declared = _declaration(root, store);
  if (declared.isEmpty) {
    return DVPublishPlan.refused(store, <String>[
      'This project declares nothing under dartvel.publish.$store in '
          'pubspec.yaml, so there is nowhere to publish to and nothing to '
          'publish with.',
    ]);
  }

  switch (store) {
    case 'play':
      return _play(root, declared);
    case 'appstore':
    case 'testflight':
      return _appStore(store, root, declared, host);
    default:
      return _firebase(root, declared);
  }
}

DVPublishPlan _play(String root, Map<Object?, Object?> declared) {
  final List<String> problems = <String>[];
  final String track = '${declared['track'] ?? 'internal'}';
  if (!dvPlayTracks.contains(track)) {
    // Not corrected to the nearest: "staging" could mean internal or alpha,
    // and guessing puts a build in front of the wrong people.
    problems.add('dartvel.publish.play.track is "$track". Google Play '
        'publishes to ${dvPlayTracks.join(', ')}.');
  }
  final Object? credentials = declared['credentials'];
  if (credentials == null || '$credentials'.trim().isEmpty) {
    // Without it fastlane prompts, and a pipeline with no terminal waits for
    // an answer until the job's cap.
    problems.add('dartvel.publish.play.credentials names no service account '
        'key. Add it to pubspec.yaml: without one the upload stops to ask, '
        'and a pipeline has nobody to answer.');
  }

  // The bundle, not the APK. Play has taken app bundles for years and an APK
  // is refused at the end of the upload rather than the start.
  final String artifact =
      p.join(root, 'build', 'app', 'outputs', 'bundle', 'release', 'app-release.aab');
  if (problems.isNotEmpty) return DVPublishPlan.refused('play', problems);
  return DVPublishPlan(
    store: 'play',
    executable: 'fastlane',
    arguments: <String>[
      'supply',
      '--aab',
      artifact,
      '--track',
      track,
      '--json_key',
      p.join(root, '$credentials'),
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

DVPublishPlan _appStore(
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
    problems.add('Publishing to $store needs Xcode, so it runs on macOS. '
        'This is $host.');
  }
  final Object? key = declared['apiKey'];
  final Object? issuer = declared['apiIssuer'];
  if (key == null || '$key'.trim().isEmpty) {
    problems.add('dartvel.publish.$store.apiKey names no App Store Connect '
        'API key.');
  }
  if (issuer == null || '$issuer'.trim().isEmpty) {
    problems.add('dartvel.publish.$store.apiIssuer names no issuer id. The '
        'key alone does not say which account it belongs to.');
  }
  if (problems.isNotEmpty) return DVPublishPlan.refused(store, problems);

  final String artifact = p.join(root, 'build', 'ios', 'ipa', 'app.ipa');
  return DVPublishPlan(
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

DVPublishPlan _firebase(String root, Map<Object?, Object?> declared) {
  final List<String> problems = <String>[];
  final Object? app = declared['app'];
  if (app == null || '$app'.trim().isEmpty) {
    problems.add('dartvel.publish.firebase.app names no application id. '
        'App Distribution identifies a build by it, and there is no way to '
        'guess which of an account\'s applications this is.');
  }
  if (problems.isNotEmpty) return DVPublishPlan.refused('firebase', problems);

  final Object? groups = declared['groups'];
  final List<String> testers = <String>[
    if (groups is List)
      for (final Object? group in groups) '$group'
    else if (groups != null)
      '$groups',
  ];
  final String artifact =
      p.join(root, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
  return DVPublishPlan(
    store: 'firebase',
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
    final Object? publish = dartvel is Map ? dartvel['publish'] : null;
    final Object? declared = publish is Map ? publish[store] : null;
    return declared is Map ? declared : const <Object?, Object?>{};
  } catch (_) {
    // A pubspec that will not parse is the build's own message to give.
    return const <Object?, Object?>{};
  }
}
