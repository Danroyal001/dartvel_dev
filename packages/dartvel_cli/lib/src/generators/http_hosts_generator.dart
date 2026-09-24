import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVHttp;
import 'package:path/path.dart' as p;

import '../graph/module_mounts.dart';
import '../http/http_analysis.dart';
import '../secrets/secrets_analysis.dart';

/// `dartvel.http` read at generation, and the Dart the running application
/// declares its hosts from.
///
/// The block is emitted as the map it was written as and handed at startup to
/// the reader that checked it here, rather than translated into constructor
/// calls: one reader means the build and the running process cannot disagree
/// about what a key means. The file imports only dartvel_core, because the
/// generated server imports it as well as the client runtime.
class HttpHostsGenerator {
  const HttpHostsGenerator._();

  /// Reads and checks `dartvel.http` from [dv], returning the block to emit,
  /// or null when the project declares none.
  ///
  /// Throws [StateError] naming the key for anything the reader does not
  /// understand. Called before anything is generated, so a build that is
  /// going to fail leaves no half-written client behind.
  static Map<Object?, Object?>? read(Map<Object?, Object?> dv) {
    final Object? http = dv['http'];
    if (http == null) return null;
    if (http is! Map) {
      throw StateError('dartvel.http must be a map with a hosts block, not '
          '"$http".');
    }
    try {
      DVHttp.readConfig(http);
    } on ArgumentError catch (error) {
      throw StateError('${error.message}');
    }
    return http;
  }

  /// The parent's block with every mounted module's hosts folded in.
  ///
  /// A module generated from an OpenAPI document or a GraphQL schema carries
  /// the one host its calls go to. Nothing read it, so a module that was
  /// generated, mounted and imported met DV-HTTP-001 on its first request,
  /// which is every request it makes.
  ///
  /// A name that two of them claim stops the build. A host name decides a
  /// base URL and a credential, so one quietly winning would send the
  /// parent's bearer token to the module's service, or the module's calls to
  /// the parent's.
  ///
  /// Throws [StateError] naming both claimants.
  static Map<Object?, Object?>? merge({
    required Map<Object?, Object?>? http,
    required List<DVModuleMount> modules,
  }) {
    final Map<Object?, Object?> hosts = <Object?, Object?>{};
    final Map<String, String> claimed = <String, String>{};
    void take(String by, Map<Object?, Object?> block) {
      final Object? declared = block['hosts'];
      if (declared is! Map) return;
      for (final MapEntry<Object?, Object?> entry in declared.entries) {
        final String name = '${entry.key}';
        final String? previous = claimed[name];
        if (previous != null) {
          throw StateError(
            'The host "$name" is declared by $previous and by $by. A host '
            'name decides a base URL and a credential, so one of them '
            'winning would send a call or a token to the wrong service. '
            'Rename one of them.',
          );
        }
        claimed[name] = by;
        hosts[name] = entry.value;
      }
    }

    if (http != null) take('this project', http);
    for (final DVModuleMount module in modules) {
      final Map<Object?, Object?>? block = module.http;
      if (block == null) continue;
      take('the ${module.id} module', block);
    }
    if (hosts.isEmpty) return http;
    final Map<Object?, Object?> merged = <Object?, Object?>{
      if (http != null) ...http,
      'hosts': hosts,
    };
    // Through the same reader, so a module's block is held to what the
    // parent's is held to rather than trusted because it was generated.
    try {
      DVHttp.readConfig(merged);
    } on ArgumentError catch (error) {
      throw StateError('${error.message}');
    }
    return merged;
  }

  /// `DV-HTTP-001` and `DV-HTTP-005` over the project's own sources, before
  /// anything is written.
  ///
  /// Client-reachable means lib/ minus [backendDir] and the generated client,
  /// the same split the DV-SECRETS-001 check makes.
  static void check({
    required String root,
    required String backendDir,
    required Map<Object?, Object?>? http,
  }) {
    final Directory lib = Directory(p.join(root, 'lib'));
    if (!lib.existsSync()) return;
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    final String backend = p.posix.normalize(backendDir.replaceAll(r'\', '/'));
    final Map<String, String> clientFiles = <String, String>{};
    final Map<String, String> backendFiles = <String, String>{};
    for (final FileSystemEntity entity
        in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String rel =
          p.relative(entity.path, from: root).replaceAll(r'\', '/');
      if (rel.startsWith('lib/dartvel_client/')) continue;
      if (rel == backend || rel.startsWith('$backend/')) {
        backendFiles[rel] = entity.readAsStringSync();
      } else {
        clientFiles[rel] = entity.readAsStringSync();
      }
    }
    final List<DVHttpFinding> findings = dvAnalyseHttp(
      hosts: http == null ? const {} : DVHttp.readConfig(http),
      secrets: pubspec.existsSync()
          ? dvParseSecretDeclarations(pubspec.readAsStringSync())
          : const <String, DVSecretDeclaration>{},
      clientFiles: clientFiles,
      backendFiles: backendFiles,
    );
    if (findings.isEmpty) return;
    throw StateError(findings.join('\n'));
  }

  /// Writes `http.g.dart` under `lib/dartvel_client`, whether or not hosts are
  /// declared: the client runtime and the generated server call it
  /// unconditionally.
  static void generate({
    required String root,
    required Map<Object?, Object?>? http,
  }) {
    final Directory out = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    File(p.join(out.path, 'http.g.dart')).writeAsStringSync(render(http));
  }

  static String render(Map<Object?, Object?>? http) {
    final StringBuffer sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln();
    if (http == null) {
      sb
        ..writeln('/// Declares nothing: this project has no `dartvel.http` block, so')
        ..writeln('/// every `DV.Http` request is refused with DV-HTTP-001 until a host is')
        ..writeln('/// declared.')
        ..writeln('void configureDartvelHttp() {}');
      return sb.toString();
    }
    sb
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln()
      ..writeln('/// `dartvel.http` from pubspec.yaml, as read and checked when this file')
      ..writeln('/// was generated.')
      ..writeln('const Map<String, Object?> dartvelHttpConfig = ${_literal(http, '')};')
      ..writeln()
      ..writeln('/// Declares every host in `dartvel.http.hosts` on `DV.Http`.')
      ..writeln('///')
      ..writeln('/// Called by the generated client runtime and by every generated server')
      ..writeln('/// role before either runs application code, so `DV.Http.host(name)` and')
      ..writeln('/// an absolute URL under a declared base URL work on both sides.')
      ..writeln('void configureDartvelHttp() {')
      ..writeln('  const DVHttp().declareFromConfig(dartvelHttpConfig);')
      ..writeln('}');
    return sb.toString();
  }

  static String _literal(Object? value, String indent) {
    if (value == null) return 'null';
    if (value is bool || value is int) return '$value';
    if (value is double) {
      return value.isFinite ? '$value' : _string('$value');
    }
    if (value is Map) {
      if (value.isEmpty) return '<String, Object?>{}';
      final String inner = '$indent  ';
      final StringBuffer sb = StringBuffer('<String, Object?>{\n');
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        sb.writeln('$inner${_string('${entry.key}')}: '
            '${_literal(entry.value, inner)},');
      }
      sb.write('$indent}');
      return sb.toString();
    }
    if (value is List) {
      return '<Object?>[${value.map((Object? v) => _literal(v, indent)).join(', ')}]';
    }
    return _string('$value');
  }

  static String _string(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";
}
