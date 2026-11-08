/// DV-RUN-007: a `@DVBoot` function that awaits the network before the
/// first frame (NEW_SPEC.md, Application Entry).
///
/// Nothing before `ready` waits on the network: a handshake, a flag sync, an
/// OTA check and a token refresh are deferred start-up work. Boot functions
/// run in phase 4, before the app's first frame, so one that awaits a request
/// holds the launch for as long as the request takes -- forever, in a lift.
///
/// Only what the source states is read: an `await` whose expression is a
/// request through `DV.Http`, `DVHttp()`, `package:http` or `HttpClient`,
/// written in the boot function itself. A request made by a function it
/// calls is a false negative here; reporting a guess would add findings
/// about calls that may not reach the network at all.
library dartvel_cli.analysis.boot_network;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../generators/client_generator.dart' show ClientGenerator, DVBootHook;
import 'dart_source_lexer.dart';

/// One boot function that waits on the network.
class DVBootNetworkFinding {
  const DVBootNetworkFinding({
    required this.file,
    required this.line,
    required this.function,
  });

  String get code => 'DV-RUN-007';

  /// Relative to the project, with forward slashes.
  final String file;

  /// 1-based: the line of the awaited request.
  final int line;

  /// The `@DVBoot` function's name.
  final String function;

  @override
  String toString() => '$code $file:$line: @DVBoot $function awaits the '
      'network before the first frame; start it without awaiting, or move it '
      'after ready, so a slow connection cannot hold the launch.';
}

final RegExp _awaitedRequest = RegExp(
  r'\bawait\s+(?:\(\s*)*(?:DV\s*\.\s*Http\b|DVHttp\s*\(|http\s*\.\s*(?:get|post|put|patch|delete|head|read|readBytes|send)\s*\(|HttpClient\s*\()',
);

/// Every DV-RUN-007 finding in the project at [root], in path order then
/// declaration order. Only boot functions the app entry runs are read: one
/// limited to other entries has no first frame to hold.
List<DVBootNetworkFinding> dvBootNetworkFindings(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  final Object? doc =
      pubspec.existsSync() ? loadYaml(pubspec.readAsStringSync()) : null;
  final Object? name = doc is Map ? doc['name'] : null;
  final List<DVBootNetworkFinding> found = <DVBootNetworkFinding>[];
  for (final DVBootHook hook in ClientGenerator.bootHooks(
    root: root,
    pkgName: name is String ? name : 'app',
    aliasPrefix: 'boot',
  )) {
    if (!hook.runsIn('app')) continue;
    // Comments and string contents masked, so words about a request are not
    // a request.
    final String masked = dvDartSourceView(hook.body).masked;
    for (final RegExpMatch match in _awaitedRequest.allMatches(masked)) {
      found.add(DVBootNetworkFinding(
        file: hook.rel,
        line: hook.bodyLine +
            '\n'.allMatches(masked.substring(0, match.start)).length,
        function: hook.function,
      ));
    }
  }
  return found;
}
