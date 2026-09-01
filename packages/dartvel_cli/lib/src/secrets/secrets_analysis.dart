/// DV-SECRETS-001, and the declaration it is checked against.
///
/// A secret compiled into a client bundle ships to every visitor. Because
/// Dartvel compiles both ends from one project it can make that a build error
/// rather than a code-review habit -- no stack assembled from separate
/// frontend and backend repositories can.
///
/// This is the advisory layer. The structural guarantee is elsewhere: only
/// PUBLIC_-prefixed values reach the generated env.g.dart and the web
/// implementation resolves the process environment to nothing at all. That
/// holds whether or not this analysis runs, which is why a value routed
/// through an indirection this cannot follow is a false negative rather than
/// a hole.
library dartvel_cli.secrets.secrets_analysis;

import 'package:yaml/yaml.dart';

enum DVSecretScope { backend, client }

/// One declared secret: a name and a scope, never a value.
class DVSecretDeclaration {
  const DVSecretDeclaration({
    required this.name,
    required this.scope,
    required this.required,
  });

  final String name;
  final DVSecretScope scope;

  /// The environments this must resolve in before a deploy may proceed.
  final Set<String> required;
}

/// A problem worth failing a build over.
class DVSecretFinding {
  const DVSecretFinding({
    required this.code,
    required this.file,
    required this.secret,
    required this.message,
  });

  final String code;
  final String file;
  final String secret;
  final String message;

  @override
  String toString() => '$code $file: $message';
}

/// Reads `dartvel.secrets` out of a pubspec.
Map<String, DVSecretDeclaration> dvParseSecretDeclarations(String pubspec) {
  final Object? doc = loadYaml(pubspec);
  if (doc is! YamlMap) return <String, DVSecretDeclaration>{};
  final Object? dartvel = doc['dartvel'];
  if (dartvel is! YamlMap) return <String, DVSecretDeclaration>{};
  final Object? secrets = dartvel['secrets'];
  if (secrets is! YamlMap) return <String, DVSecretDeclaration>{};

  final Map<String, DVSecretDeclaration> out = <String, DVSecretDeclaration>{};
  for (final MapEntry<Object?, Object?> entry in secrets.entries) {
    final String name = '${entry.key}';
    final Object? body = entry.value;

    // Backend-scoped by default, and that default is the whole posture: a
    // secret nobody thought about must not be the one that ships.
    DVSecretScope scope = DVSecretScope.backend;
    final Set<String> required = <String>{};

    if (body is YamlMap) {
      if ('${body['scope']}' == 'client') scope = DVSecretScope.client;
      final Object? envs = body['required'];
      if (envs is YamlList) {
        for (final Object? env in envs) {
          required.add('$env');
        }
      }
    }

    out[name] = DVSecretDeclaration(
      name: name,
      scope: scope,
      required: required,
    );
  }
  return out;
}

/// Problems with the declaration itself.
List<String> dvValidateDeclarations(
  Map<String, DVSecretDeclaration> declared,
) {
  final List<String> problems = <String>[];
  for (final DVSecretDeclaration secret in declared.values) {
    // One client opt-in, not two. The prefix is the marker in the environment
    // and in the generated env.g.dart, and the declaration is where it is
    // justified -- letting them disagree means the bundle and the declaration
    // say different things about the same name.
    if (secret.scope == DVSecretScope.client &&
        !secret.name.startsWith('PUBLIC_')) {
      problems.add(
        '"${secret.name}" is declared scope: client but does not start with '
        'PUBLIC_. Rename it to PUBLIC_${secret.name}, or drop the client '
        'scope if it is not meant to ship to the browser.',
      );
    }
  }
  return problems;
}

/// Every secret name reached through `DV.Secrets` in [source].
Set<String> dvExtractSecretUses(String source) {
  final String stripped = _stripComments(source);
  final RegExp pattern = RegExp(
    r'''DV\.Secrets\.(?:get|maybeGet|getOr|has)\s*\(\s*(['"])(.*?)\1''',
  );

  final Set<String> used = <String>{};
  for (final RegExpMatch match in pattern.allMatches(stripped)) {
    final String name = match.group(2)!;
    if (name.isEmpty) continue;
    // A name assembled at runtime cannot be checked, and reporting the
    // literal fragment would be a finding about a secret that does not exist.
    if (name.contains(r'$')) continue;
    used.add(name);
  }
  return used;
}

String _stripComments(String source) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < source.length) {
    if (source[i] == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        i += 1;
      }
      continue;
    }
    if (source[i] == '/' && i + 1 < source.length && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < source.length &&
          !(source[i] == '*' && source[i + 1] == '/')) {
        i += 1;
      }
      i += 2;
      continue;
    }
    out.write(source[i]);
    i += 1;
  }
  return out.toString();
}

/// Backend secrets reached from client-reachable code, and undeclared names.
///
/// [clientFiles] is path to source for everything the client bundle can reach
/// -- in a Dartvel project, lib/ minus the backend directory.
List<DVSecretFinding> dvAnalyseSecrets({
  required Map<String, DVSecretDeclaration> declared,
  required Map<String, String> clientFiles,
}) {
  final List<DVSecretFinding> findings = <DVSecretFinding>[];

  final List<String> paths = clientFiles.keys.toList()..sort();
  for (final String path in paths) {
    for (final String name in dvExtractSecretUses(clientFiles[path]!).toList()
      ..sort()) {
      final DVSecretDeclaration? secret = declared[name];

      if (secret == null) {
        findings.add(DVSecretFinding(
          code: 'DV-SECRETS-002',
          file: path,
          secret: name,
          message: '"$name" is not declared. Add it under dartvel.secrets in '
              'pubspec.yaml, with a scope. A name that is only ever typed at '
              'the call site fails at runtime in production instead.',
        ));
        continue;
      }

      if (secret.scope == DVSecretScope.backend) {
        findings.add(DVSecretFinding(
          code: 'DV-SECRETS-001',
          file: path,
          secret: name,
          message: '"$name" is backend-scoped and is reached from client code. '
              'A secret in a client bundle ships to every visitor. Fetch it '
              'through a backend function, or declare it scope: client with a '
              'PUBLIC_ prefix if it is genuinely publishable.',
        ));
      }
    }
  }
  return findings;
}

/// Declared secrets required for [environment] that did not resolve.
///
/// Checked against the declaration, so a secret forgotten in a new
/// environment fails the deploy rather than the first request that needs it.
List<String> dvValidateEnvironment({
  required Map<String, DVSecretDeclaration> declared,
  required String environment,
  required Set<String> resolved,
}) {
  final List<String> problems = <String>[];
  final List<String> names = declared.keys.toList()..sort();
  for (final String name in names) {
    final DVSecretDeclaration secret = declared[name]!;
    if (!secret.required.contains(environment)) continue;
    if (resolved.contains(name)) continue;
    problems.add(
      '"$name" is required in $environment and does not resolve. Set it in '
      'the environment, or remove $environment from its required list.',
    );
  }
  return problems;
}
