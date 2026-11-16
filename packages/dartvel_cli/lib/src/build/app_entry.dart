/// The entry `dartvel build` and `dartvel dev` hand Flutter.
///
/// `DV.run()` takes nothing: `void main() => DV.run();` is the whole of a pure
/// application's main.dart (owner, 14 Oct 2026). The process's arguments --
/// a file opened with the app, a dartvel:// link, a command for a command
/// entry -- reach Dart only through a `main(List<String>)`, so the generator
/// writes `lib/dartvel_client/main.g.dart`, which keeps them for DV.run and
/// calls the application's own main, and the build compiles that.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the generated entry is written, relative to the project.
const String dvAppEntryPath = 'lib/dartvel_client/main.g.dart';

/// The generated entry for [root], or null when there is none (a project
/// with no lib/main.dart, or one not generated yet).
String? dvAppEntryTarget(String root) =>
    File(p.join(root, dvAppEntryPath)).existsSync() ? dvAppEntryPath : null;

/// The generated entry's source, for package [package] whose lib/main.dart
/// is [mainSource].
///
/// An application still written as `main(List<String> args)` is called with
/// them, so a project generated before this change keeps building.
String dvAppEntrySource(String package, String mainSource) {
  final bool takesArguments =
      RegExp(r'\bmain\s*\(\s*List\s*<\s*String\s*>').hasMatch(mainSource);
  return '''
// GENERATED – do not edit.
//
// The entry dartvel build and dartvel dev compile. It keeps this process's
// arguments for DV.run() and calls the application's own main.
import 'package:dartvel_flutter/dartvel_flutter.dart' show dvSetLaunchArguments;
import 'package:$package/main.dart' as app;

void main(List<String> args) {
  dvSetLaunchArguments(args);
  app.main(${takesArguments ? 'args' : ''});
}
''';
}
