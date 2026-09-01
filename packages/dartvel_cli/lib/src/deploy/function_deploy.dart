/// Function mode: deploying each backend function on its own.
///
/// `dartvel deploy` could push a web build to a hosting provider. The spec
/// also lists function mode -- "each backend function can be deployed
/// independently" to Lambda, Cloud Run, containers, edge runtimes, Fly,
/// Railway or bare metal -- and none of it existed.
///
/// Calling a cloud needs credentials. Producing the artifacts does not, and
/// that is the part that is wrong or right regardless of who runs it: a
/// handler name a provider rejects, a port the container never listens on, a
/// manifest missing the function it was generated for.
library dartvel_cli.deploy.function_deploy;

import 'dart:convert';

/// The targets function mode understands.
const List<String> dvFunctionDeployTargets = <String>[
  'lambda',
  'cloud-run',
  'container',
  'edge',
  'fly',
  'railway',
  'bare-metal',
];

/// A backend function, as far as deployment cares.
class DVDeployableFunction {
  const DVDeployableFunction({
    required this.name,
    required this.method,
    required this.path,
    required this.source,
  });

  final String name;
  final String method;
  final String path;
  final String source;
}

/// One function and the name it will carry at the provider.
class DVDeployUnit {
  const DVDeployUnit({required this.function, required this.remoteName});

  final DVDeployableFunction function;

  /// Sanitised for the provider.
  ///
  /// Lambda allows letters, digits, hyphen and underscore up to 64
  /// characters, and a route like /api/users/:id is none of those. Left raw,
  /// the rejection arrives from the cloud rather than from here.
  final String remoteName;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': function.name,
        'remoteName': remoteName,
        'method': function.method,
        'path': function.path,
        'source': function.source,
      };
}

/// The files to write for a deployment.
class DVFunctionDeployPlan {
  const DVFunctionDeployPlan({
    required this.target,
    required this.units,
    required this.files,
  });

  final String target;
  final List<DVDeployUnit> units;

  /// Relative path to content.
  final Map<String, String> files;
}

/// Builds the deployment artifacts for [target].
DVFunctionDeployPlan dvFunctionDeployPlan({
  required List<DVDeployableFunction> functions,
  required String target,
  required String appName,
  int port = 8080,
  Set<String> secretNames = const <String>{},
}) {
  if (!dvFunctionDeployTargets.contains(target)) {
    // Named, rather than producing nothing and reporting success -- which is
    // how a typo becomes a deploy that quietly did not happen.
    throw ArgumentError.value(
      target,
      'target',
      'unknown function deploy target. Known: '
          '${dvFunctionDeployTargets.join(', ')}',
    );
  }
  if (functions.isEmpty) {
    throw ArgumentError.value(
      functions,
      'functions',
      'there are no backend functions to deploy',
    );
  }

  final List<DVDeployUnit> units = _units(functions, appName);

  final Map<String, String> files = <String, String>{
    'dartvel-deploy.json': _manifest(
      target: target,
      appName: appName,
      units: units,
      port: port,
      secretNames: secretNames,
    ),
  };

  switch (target) {
    case 'container':
    case 'railway':
    case 'bare-metal':
      files['Dockerfile'] = _dockerfile(port: '$port', exposed: '$port');
    case 'cloud-run':
      // Cloud Run assigns PORT. A container that hardcodes one is marked
      // unhealthy and rolled back, with nothing in the logs to say why.
      files['Dockerfile'] = _dockerfile(port: r'$PORT', exposed: '8080');
    case 'fly':
      files['Dockerfile'] = _dockerfile(port: '$port', exposed: '$port');
      files['fly.toml'] = _flyToml(appName: appName, port: port);
    case 'lambda':
    case 'edge':
      // No container: each unit is its own bundle, described by the manifest.
      break;
  }

  return DVFunctionDeployPlan(target: target, units: units, files: files);
}

List<DVDeployUnit> _units(
  List<DVDeployableFunction> functions,
  String appName,
) {
  final Set<String> taken = <String>{};
  final List<DVDeployUnit> units = <DVDeployUnit>[];

  for (final DVDeployableFunction function in functions) {
    var candidate = _sanitise('$appName-${function.name}');
    // Two functions must never collide: the second deploy would overwrite the
    // first and both routes would answer with one handler.
    var suffix = 2;
    while (!taken.add(candidate)) {
      candidate = _sanitise('$appName-${function.name}-$suffix');
      suffix += 1;
    }
    units.add(DVDeployUnit(function: function, remoteName: candidate));
  }
  return units;
}

String _sanitise(String value) {
  final StringBuffer out = StringBuffer();
  for (final int unit in value.codeUnits) {
    final bool digit = unit >= 0x30 && unit <= 0x39;
    final bool upper = unit >= 0x41 && unit <= 0x5a;
    final bool lower = unit >= 0x61 && unit <= 0x7a;
    final bool dash = unit == 0x2d || unit == 0x5f;
    out.writeCharCode(digit || upper || lower || dash ? unit : 0x2d);
  }

  // Collapsed, so /api/users/:id does not become a run of hyphens, and
  // trimmed because a leading or trailing one is rejected too.
  var name = out.toString().replaceAll(RegExp('-+'), '-');
  while (name.startsWith('-')) {
    name = name.substring(1);
  }
  while (name.endsWith('-')) {
    name = name.substring(0, name.length - 1);
  }
  if (name.length > 64) name = name.substring(0, 64);
  return name.isEmpty ? 'dartvel-function' : name;
}

String _manifest({
  required String target,
  required String appName,
  required List<DVDeployUnit> units,
  required int port,
  required Set<String> secretNames,
}) {
  final List<String> secrets = secretNames.toList()..sort();
  return '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'app': appName,
        'target': target,
        'port': port,
        // Names only, never values. A deployment descriptor is committed and
        // read by CI; a value in one is a value in the repository.
        'secrets': secrets,
        'functions': <Object?>[
          for (final DVDeployUnit unit in units) unit.toJson(),
        ],
      })}\n';
}

String _dockerfile({required String port, required String exposed}) => '''
# GENERATED by dartvel deploy --functions -- do not edit.
FROM debian:stable-slim
RUN apt-get update \\
 && apt-get install -y --no-install-recommends ca-certificates \\
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY build/ /app/
# The port the server binds and the port the image publishes are the same
# number deliberately: a container listening on one and publishing another
# starts cleanly and answers nothing.
ENV DARTVEL_PORT=$port
EXPOSE $exposed
CMD ["/app/server"]
''';

String _flyToml({required String appName, required int port}) => '''
# GENERATED by dartvel deploy --functions -- do not edit.
app = "$appName"

[build]
  dockerfile = "Dockerfile"

[http_service]
  internal_port = $port
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
''';
