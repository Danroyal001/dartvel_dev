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

import 'package:dartvel_core/dartvel.dart';
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

    // And the other direction, which is the one that leaks. Whatever writes
    // env.g.dart decides by prefix alone: the router builder runs under
    // build_runner with the .env file and no pubspec declaration in reach, so
    // a backend-scoped name spelled PUBLIC_ is compiled into the bundle while
    // the declaration promises it stays on the server. DV-SECRETS-001 does
    // not catch it either, because the value arrives through a generated
    // constant rather than a DV.Secrets call the analysis can read. Refusing
    // the contradiction is what keeps prefix and declaration from disagreeing.
    if (secret.scope == DVSecretScope.backend &&
        secret.name.startsWith('PUBLIC_')) {
      problems.add(
        '"${secret.name}" is backend-scoped but is spelled with the PUBLIC_ '
        'prefix, which is what puts a value into the generated env.g.dart and '
        'so into the client bundle. Rename it without the prefix, or declare '
        'it scope: client if shipping it to every visitor is intended.',
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
/// -- in a Dartvel project, lib/ minus the backend directory. [backendFiles]
/// is the rest, checked for undeclared names only: reaching a backend-scoped
/// secret from the backend is the arrangement working, and a diagnostic that
/// fires on correct code gets suppressed project-wide.
List<DVSecretFinding> dvAnalyseSecrets({
  required Map<String, DVSecretDeclaration> declared,
  required Map<String, String> clientFiles,
  Map<String, String> backendFiles = const <String, String>{},
}) {
  final List<DVSecretFinding> findings = <DVSecretFinding>[];

  final List<String> paths = clientFiles.keys.toList()..sort();
  for (final String path in paths) {
    for (final String name in dvExtractSecretUses(clientFiles[path]!).toList()
      ..sort()) {
      final DVSecretDeclaration? secret = declared[name];

      if (secret == null) {
        findings.add(_undeclared(path, name));
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

  // The backend is where secrets are meant to be read, which made it the one
  // place a misspelled name went unchecked -- and a misspelled name is the
  // failure the declaration exists to move out of production and into the
  // build.
  final List<String> backendPaths = backendFiles.keys.toList()..sort();
  for (final String path in backendPaths) {
    for (final String name in dvExtractSecretUses(backendFiles[path]!).toList()
      ..sort()) {
      if (declared.containsKey(name)) continue;
      findings.add(_undeclared(path, name));
    }
  }
  return findings;
}

DVSecretFinding _undeclared(String path, String name) => DVSecretFinding(
      code: 'DV-SECRETS-002',
      file: path,
      secret: name,
      message: '"$name" is not declared. Add it under dartvel.secrets in '
          'pubspec.yaml, with a scope. A name that is only ever typed at the '
          'call site fails at runtime in production instead.',
    );

/// PUBLIC_ variables in an env file that the declaration does not account for.
///
/// Whatever writes `env.g.dart` compiles in every PUBLIC_-prefixed variable it
/// finds, and that is the whole of the decision -- no declaration is consulted
/// and none is in reach under build_runner. So a name somebody typed with the
/// prefix reaches every visitor with nothing having reviewed it: copied from
/// another project, guessed at, or written before anyone thought about the
/// scope. The declaration is meant to be where the client opt-in is
/// justified, and this is what makes that so rather than aspirational.
///
/// Names without the prefix are not reported. They never reach the bundle, so
/// flagging them would turn a security diagnostic into a tidiness one, and
/// those get switched off together.
///
/// [contents] rather than a path, and read with the parser the runtime uses,
/// so this and the generator cannot disagree about what the file says.
List<DVSecretFinding> dvAnalysePublicEnvironment({
  required Map<String, DVSecretDeclaration> declared,
  required String file,
  required String contents,
}) {
  final List<DVSecretFinding> findings = <DVSecretFinding>[];
  final List<String> names = dvParseEnvContents(contents).keys.toList()..sort();
  for (final String name in names) {
    if (!name.startsWith('PUBLIC_')) continue;
    if (declared[name]?.scope == DVSecretScope.client) continue;

    // The value is never quoted back. A diagnostic that prints the secret to
    // prove it found one has put it in the build log, where CI keeps it for
    // everybody with access to the repository.
    findings.add(DVSecretFinding(
      code: 'DV-SECRETS-003',
      file: file,
      secret: name,
      message: '"$name" carries the PUBLIC_ prefix, so it is compiled into '
          'env.g.dart and ships to every visitor, but no dartvel.secrets '
          'entry declares it scope: client. Declare it, or rename it without '
          'the prefix so it stays on the server.',
    ));
  }
  return findings;
}

/// Which of [names] resolve, asked of the same resolver the deployed process
/// will use.
///
/// Not a reader of its own. The gate had one, it did not understand the
/// `export KEY=value` form, and so it failed a deploy over a secret the
/// running process resolves without trouble -- and the thing people do with
/// a gate that is wrong is stop trusting it. Routing through [DVSecrets]
/// means the check and the process it is gating cannot disagree, because
/// there is only one answer to give.
///
/// Values are dropped again before returning. The gate runs inside the
/// process that goes on to build and write the deployment artifacts, and a
/// secret left loaded is a secret that can reach one.
Set<String> dvResolveSecrets(Iterable<String> names, {String? envFile}) {
  if (envFile != null) DVSecrets.useEnvFile(envFile);
  try {
    return <String>{
      for (final String name in names)
        if (const DVSecrets().has(name)) name,
    };
  } finally {
    DVSecrets.reset();
  }
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
