/// The Dartvel Cloud protocol: the requests `dartvel build --cloud`,
/// `dartvel publish --cloud` and `dartvel key cloud` make, and the answers the
/// Cloud service gives.
///
/// Pure Dart with no `dart:io`, so the CLI and the service read one set of
/// definitions. A field added on one side and not the other is the drift this
/// file exists to prevent: the build that was queued is the build that was
/// asked for, or it is refused when it arrives.
///
/// Version 1, over HTTPS with a bearer token:
///
/// | Request | Answer |
/// |---|---|
/// | `POST /api/v1/builds` with the spec as `X-Dartvel-Build` JSON and the source zip as the body | 201 and a [DVCloudBuild] |
/// | `GET /api/v1/builds/<id>` | a [DVCloudBuild] |
/// | `GET /api/v1/builds/<id>/events` (`Last-Event-ID` resumes) | a `text/event-stream` of [DVCloudEvent]s |
/// | `GET /api/v1/builds/<id>/artifacts/<name>` | the artifact's bytes |
/// | `PUT /api/v1/projects/<project>/credentials/<name>` with the value as the body | 204 |
/// | `GET /api/v1/projects/<project>/credentials` | the names that are set, never the values |
/// | `DELETE /api/v1/projects/<project>/credentials/<name>` | 204 |
///
/// A refusal is JSON with `code`, `message` and, where there is somewhere to
/// go next, `url` ([DVCloudRefusal]). Every cloud build needs a paid plan:
/// an account without one is answered 402 with the code `plan_required`.
library;

import 'dart:convert';

/// The hosted Dartvel Cloud service, where the CLI sends a cloud request.
/// `DARTVEL_CLOUD_URL` replaces it, for Dartvel's own staging and tests.
const String dvCloudDefaultUrl = 'https://cloud.dartvel.dev';

/// Where an account without a plan is sent.
const String dvCloudPlansUrl = 'https://dartvel.dev/cloud#plans';

/// The protocol version in every path.
const String dvCloudApiVersion = 'v1';

/// The header a build request carries its [DVCloudBuildSpec] in, as JSON, so
/// the body can be the source archive and nothing else.
const String dvCloudBuildHeader = 'X-Dartvel-Build';

/// The environment variables the CLI reads.
const String dvCloudUrlVariable = 'DARTVEL_CLOUD_URL';
const String dvCloudTokenVariable = 'DARTVEL_CLOUD_TOKEN';

enum DVCloudWorkerOs { linux, macos, windows }

/// The worker operating system each target builds on.
const Map<String, DVCloudWorkerOs> dvCloudTargets = <String, DVCloudWorkerOs>{
  'android': DVCloudWorkerOs.linux,
  'ios': DVCloudWorkerOs.macos,
  'macos': DVCloudWorkerOs.macos,
  'windows': DVCloudWorkerOs.windows,
  'linux': DVCloudWorkerOs.linux,
  'web': DVCloudWorkerOs.linux,
  'web-server': DVCloudWorkerOs.linux,
};

DVCloudWorkerOs? dvCloudWorkerOs(String target) => dvCloudTargets[target];

/// The profiles `dartvel build --profile` takes.
const List<String> dvCloudProfiles = <String>['development', 'profile', 'release'];

/// The stores `dartvel publish` knows.
const List<String> dvCloudStores = <String>['play', 'appstore', 'testflight', 'firebase'];

final RegExp _projectName = RegExp(r'^[a-z_][a-z0-9_]{0,63}$');

/// A project is named as its pubspec.yaml names the package.
bool dvCloudIsProjectName(String name) => _projectName.hasMatch(name);

enum DVCloudBuildStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled;

  bool get isFinished => this != queued && this != running;

  static DVCloudBuildStatus parse(Object? value) {
    for (final DVCloudBuildStatus s in values) {
      if (s.name == value) return s;
    }
    throw FormatException('"$value" is not a build status.');
  }
}

String _string(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String) throw FormatException('"$key" must be a string.');
  return value;
}

/// What to build.
class DVCloudBuildSpec {
  const DVCloudBuildSpec({
    required this.project,
    required this.target,
    this.profile = 'release',
    this.publish,
    this.dryRun = false,
  });

  final String project;
  final String target;
  final String profile;

  /// A store `dartvel publish` sends the build to once it is built.
  final String? publish;

  /// Passed to that publish as `--dry-run`.
  final bool dryRun;

  Map<String, Object?> toJson() => <String, Object?>{
        'project': project,
        'target': target,
        'profile': profile,
        if (publish != null) 'publish': publish,
        if (dryRun) 'dryRun': true,
      };

  factory DVCloudBuildSpec.fromJson(Map<String, Object?> json) {
    final String project = _string(json, 'project');
    if (!dvCloudIsProjectName(project)) {
      throw FormatException('"$project" is not a project name.');
    }
    final String target = _string(json, 'target');
    if (!dvCloudTargets.containsKey(target)) {
      throw FormatException('"$target" does not build in the cloud. '
          'Targets: ${dvCloudTargets.keys.join(', ')}.');
    }
    final String profile = json['profile'] == null ? 'release' : _string(json, 'profile');
    if (!dvCloudProfiles.contains(profile)) {
      throw FormatException('"$profile" is not a build profile.');
    }
    final Object? publish = json['publish'];
    if (publish != null && !dvCloudStores.contains(publish)) {
      throw FormatException('"$publish" is not a store Dartvel publishes to.');
    }
    return DVCloudBuildSpec(
      project: project,
      target: target,
      profile: profile,
      publish: publish as String?,
      dryRun: json['dryRun'] == true,
    );
  }
}

/// A file a build produced, named relative to the target's output directory.
class DVCloudArtifact {
  const DVCloudArtifact({required this.name, required this.size, required this.sha256});

  final String name;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() =>
      <String, Object?>{'name': name, 'size': size, 'sha256': sha256};

  /// A name is written under the client's own directory, so one that climbs
  /// out of it, or is absolute, is refused before anything is written.
  static bool isSafeName(String name) =>
      name.isNotEmpty &&
      !name.startsWith('/') &&
      !name.contains(r'\') &&
      !name.split('/').any((String s) => s.isEmpty || s == '.' || s == '..');

  factory DVCloudArtifact.fromJson(Map<String, Object?> json) {
    final String name = _string(json, 'name');
    if (!isSafeName(name)) throw FormatException('"$name" is not an artifact name.');
    final Object? size = json['size'];
    if (size is! num) throw const FormatException('"size" must be a number.');
    return DVCloudArtifact(name: name, size: size.toInt(), sha256: _string(json, 'sha256'));
  }
}

class DVCloudBuild {
  const DVCloudBuild({
    required this.id,
    required this.spec,
    required this.status,
    this.queuePosition,
    this.artifacts = const <DVCloudArtifact>[],
    this.installUrl,
    this.message,
  });

  final String id;
  final DVCloudBuildSpec spec;
  final DVCloudBuildStatus status;

  /// Builds ahead of this one, while it is queued.
  final int? queuePosition;
  final List<DVCloudArtifact> artifacts;

  /// A page testers open on a device to install a development or preview
  /// build, when the service offers one.
  final String? installUrl;

  /// Why a build failed or was cancelled, in a sentence.
  final String? message;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'spec': spec.toJson(),
        'status': status.name,
        if (queuePosition != null) 'queuePosition': queuePosition,
        'artifacts': <Object?>[for (final DVCloudArtifact a in artifacts) a.toJson()],
        if (installUrl != null) 'installUrl': installUrl,
        if (message != null) 'message': message,
      };

  factory DVCloudBuild.fromJson(Map<String, Object?> json) {
    final Object? spec = json['spec'];
    if (spec is! Map) throw const FormatException('"spec" must be an object.');
    final Object? artifacts = json['artifacts'];
    final Object? position = json['queuePosition'];
    return DVCloudBuild(
      id: _string(json, 'id'),
      spec: DVCloudBuildSpec.fromJson(spec.cast<String, Object?>()),
      status: DVCloudBuildStatus.parse(json['status']),
      queuePosition: position is num ? position.toInt() : null,
      artifacts: <DVCloudArtifact>[
        if (artifacts is List)
          for (final Object? a in artifacts)
            if (a is Map) DVCloudArtifact.fromJson(a.cast<String, Object?>()),
      ],
      installUrl: json['installUrl'] as String?,
      message: json['message'] as String?,
    );
  }
}

/// One event on a build's stream: a line of its log, or a change of status.
class DVCloudEvent {
  const DVCloudEvent.log(this.id, String this.line) : status = null;
  const DVCloudEvent.status(this.id, DVCloudBuildStatus this.status) : line = null;

  /// Increasing per build; sent back as `Last-Event-ID` to resume.
  final int id;
  final String? line;
  final DVCloudBuildStatus? status;
}

/// [event] as server-sent-event text.
String dvCloudEncodeEvent(DVCloudEvent event) {
  final StringBuffer out = StringBuffer('id: ${event.id}\n');
  if (event.status != null) {
    out.write('event: status\ndata: ${event.status!.name}\n');
  } else {
    out.write('event: log\n');
    for (final String part in event.line!.split('\n')) {
      out.write('data: $part\n');
    }
  }
  out.write('\n');
  return out.toString();
}

/// Reads server-sent events from text arriving in chunks of any size.
class DVCloudEventParser {
  String _pending = '';
  int? _id;
  String _event = 'message';
  final List<String> _data = <String>[];

  /// The events [chunk] completes.
  List<DVCloudEvent> add(String chunk) {
    _pending += chunk;
    final List<DVCloudEvent> events = <DVCloudEvent>[];
    int newline;
    while ((newline = _pending.indexOf('\n')) >= 0) {
      String line = _pending.substring(0, newline);
      _pending = _pending.substring(newline + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.isEmpty) {
        final DVCloudEvent? event = _dispatch();
        if (event != null) events.add(event);
        continue;
      }
      if (line.startsWith(':')) continue;
      final int colon = line.indexOf(':');
      final String field = colon < 0 ? line : line.substring(0, colon);
      String value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'id':
          _id = int.tryParse(value);
        case 'event':
          _event = value;
        case 'data':
          _data.add(value);
      }
    }
    return events;
  }

  DVCloudEvent? _dispatch() {
    final int? id = _id;
    final String event = _event;
    final String data = _data.join('\n');
    final bool had = _data.isNotEmpty;
    _id = null;
    _event = 'message';
    _data.clear();
    if (!had || id == null) return null;
    if (event == 'status') {
      try {
        return DVCloudEvent.status(id, DVCloudBuildStatus.parse(data));
      } on FormatException {
        return null;
      }
    }
    return event == 'log' ? DVCloudEvent.log(id, data) : null;
  }
}

/// The credentials a project can keep in Dartvel Cloud, and what each is.
const Map<String, String> dvCloudCredentials = <String, String>{
  'android-keystore': 'The upload keystore Android release builds are signed with.',
  'android-keystore-password': 'That keystore\'s password.',
  'android-key-alias': 'The alias of the signing key in that keystore.',
  'android-key-password': 'The key\'s password, when it is not the keystore\'s.',
  'firebase-service-account': 'A service account JSON key for Firebase App Distribution.',
  'play-service-account': 'A service account JSON key for the Google Play Developer API.',
  'appstore-api-key': 'An App Store Connect API private key (.p8).',
  'appstore-api-key-id': 'That key\'s id.',
  'appstore-api-issuer': 'The issuer id of the account the key belongs to.',
  'ios-distribution-certificate': 'An iOS distribution certificate with its private key (.p12).',
  'ios-distribution-certificate-password': 'That .p12 file\'s password.',
  'ios-provisioning-profile': 'The provisioning profile iOS builds are signed with.',
};

Iterable<String> get dvCloudCredentialNames => dvCloudCredentials.keys;

bool dvCloudIsCredentialName(String name) => dvCloudCredentials.containsKey(name);

const Set<String> _platformDirectories = <String>{
  'android',
  'ios',
  'macos',
  'linux',
  'windows',
};

const Set<String> _alwaysExcluded = <String>{
  '.dart_tool',
  '.git',
  'node_modules',
  '.gradle',
  'Pods',
  '.symlinks',
};

/// Whether [path], relative to the project with `/` separators, stays out of
/// the source a cloud build uploads.
///
/// Build output and tool caches are rebuilt by the worker and are most of a
/// project's size. `.env` files are left out because they hold the values
/// Secrets and Environments exists to keep off other machines; signing and
/// store credentials go to the Cloud credential store instead.
/// `.env.example` is a template and is kept.
bool dvCloudSourceExcluded(String path) {
  final List<String> parts = path.split('/').where((String s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return true;
  if (parts.any(_alwaysExcluded.contains)) return true;
  if (parts.first == 'build') return true;
  if (_platformDirectories.contains(parts.first) && parts.contains('build')) return true;
  final String name = parts.last;
  if ((name == '.env' || name.startsWith('.env.')) && name != '.env.example') return true;
  return false;
}

/// The JSON a [DVCloudBuildSpec] travels in, in the [dvCloudBuildHeader].
String dvCloudSpecHeader(DVCloudBuildSpec spec) => jsonEncode(spec.toJson());

/// Why the service said no.
class DVCloudRefusal {
  const DVCloudRefusal({
    required this.status,
    required this.code,
    required this.message,
    this.url,
  });

  final int status;
  final String code;
  final String message;
  final String? url;

  /// Cloud builds are paid; this is the account having no plan that covers
  /// the request.
  bool get planRequired => status == 402 || code == 'plan_required';

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'message': message,
        if (url != null) 'url': url,
      };

  /// Read from any refusal, including one whose body is not the protocol's:
  /// a proxy's error page still has a status, and a 402 still means a plan.
  factory DVCloudRefusal.fromResponse(int status, Object? body) {
    final Map<Object?, Object?> json = body is Map ? body : const <Object?, Object?>{};
    final bool plan = status == 402 || json['code'] == 'plan_required';
    final Object? message = json['message'];
    final Object? url = json['url'];
    return DVCloudRefusal(
      status: status,
      code: json['code'] is String ? json['code']! as String : (plan ? 'plan_required' : 'http_$status'),
      message: message is String && message.isNotEmpty
          ? message
          : plan
              ? 'Dartvel Cloud builds need a paid plan, and this account has none.'
              : 'Dartvel Cloud answered $status.',
      url: url is String ? url : (plan ? dvCloudPlansUrl : null),
    );
  }
}
