import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show
        DVApiScopes,
        DVOAuthEndpoints,
        DVPlatformApiConfig,
        DVPlatformApiConfigError,
        DVUndefinedScopeAction;
import 'package:path/path.dart' as p;

import 'backend_generator.dart' show dvMergedLibSources;
import 'policy_classes.dart';

/// `dartvel.platformApi` read at generation, and the registry the client and
/// the generated server read it from.
///
/// Until this the CLI did not read the key at all. `DVApiScopes` could check a
/// scope against the registered policies, and nothing asked it to at build, so
/// a scope naming an action no policy defines shipped -- and every call a
/// partner made with it was refused, reading as the partner's bug.
class PlatformApiGenerator {
  const PlatformApiGenerator._();

  /// Reads and checks `dartvel.platformApi` from [dv], or returns null when
  /// the project declares none.
  ///
  /// Throws [StateError] naming the key for anything the parser does not
  /// understand. Called before anything is written.
  static DVPlatformApiConfig? read(Map<Object?, Object?> dv) {
    final Object? declared = dv['platformApi'];
    if (declared == null) return null;
    try {
      return DVPlatformApiConfig.fromConfig(_plain(declared));
    } on DVPlatformApiConfigError catch (error) {
      throw StateError(error.message);
    }
  }

  /// `DV-APIKEY-001`: a scope naming a policy action no `@DVPolicy` class in
  /// the application defines.
  ///
  /// Checked against the same policy classes the registrations are generated
  /// from, as `action:Resource`, so `Invoice.view` is not satisfied by an
  /// `OrderPolicy.view` -- the action name alone would be.
  static void check({
    required String root,
    required String pkgName,
    required String backendDir,
    required DVPlatformApiConfig config,
  }) {
    final Set<String> defined = <String>{
      for (final (String path, String source) in dvMergedLibSources(
        root,
        pkgName,
        backendDir,
      ))
        if (source.contains('@DVPolicy('))
          for (final DVPolicyClass policy in dvPolicyClassesIn(source, path))
            for (final DVPolicyMethod method in policy.methods)
              '${method.action}:${policy.resource}',
      // The framework's own actions, which the framework's endpoints check:
      // a key allowed to introspect tokens holds a scope covering this.
      DVApiScopes.policyKeyOf(DVOAuthEndpoints.introspectAction),
    };
    try {
      config.scopes.validateAgainst(defined);
    } on DVUndefinedScopeAction catch (error) {
      throw StateError(
        '$error Write the method on a @DVPolicy(Resource) class, or take the '
        'action out of the scope. Policy methods are '
        '${dvPolicyActions.join(', ')}.',
      );
    }
  }

  /// Writes `lib/dartvel_client/platform_api.g.dart`.
  ///
  /// The declaration is embedded and parsed again at startup by the parser
  /// that checked it here, so the server cannot run a different reading of
  /// the pubspec than the build refused or accepted.
  static void generate({
    required String root,
    required Map<Object?, Object?> dv,
  }) {
    final Directory out = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    File(
      p.join(out.path, 'platform_api.g.dart'),
    ).writeAsStringSync(source(dv['platformApi']));
  }

  static String source(Object? declared) {
    final StringBuffer sb = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln('library dartvel_client_platform_api;')
      ..writeln();
    if (declared == null) {
      sb
        ..writeln("import 'package:dartvel_core/dartvel.dart';")
        ..writeln()
        ..writeln(
          '/// `dartvel.platformApi` from pubspec.yaml. This project '
          'declares none,',
        )
        ..writeln('/// so no API key or OAuth token authenticates a request.')
        ..writeln('const DVPlatformApiConfig? dartvelPlatformApi = null;');
      return sb.toString();
    }
    final String json = jsonEncode(
      _plain(declared),
    ).replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$');
    sb
      ..writeln("import 'dart:convert';")
      ..writeln()
      ..writeln("import 'package:dartvel_core/dartvel.dart';")
      ..writeln()
      ..writeln(
        '/// `dartvel.platformApi` from pubspec.yaml, as `dartvel routes` '
        'checked it:',
      )
      ..writeln(
        '/// the scopes, each a set of policy actions, the rate plans '
        'and the',
      )
      ..writeln('/// OAuth provider settings.')
      ..writeln('final DVPlatformApiConfig? dartvelPlatformApi =')
      ..writeln("    DVPlatformApiConfig.fromConfig(jsonDecode('$json'));");
    return sb.toString();
  }

  /// A YAML value as plain maps, lists and scalars with string keys.
  static Object? _plain(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> e in value.entries)
          '${e.key}': _plain(e.value),
      };
    }
    if (value is List) {
      return <Object?>[for (final Object? v in value) _plain(v)];
    }
    return value;
  }
}
