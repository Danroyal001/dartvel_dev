/// What a build refuses to start.
///
/// "Never start a build that cannot finish" is the toolchain rule, and it was
/// read as being about tools: the host, the SDK, the embedder. A declaration
/// the build cannot honour is the same thing one layer up -- a kiosk policy
/// that would build a literal PIN into the artifact, a module whose project
/// is not where the declaration says -- and both were checked by
/// `dartvel doctor` alone. A pipeline that runs `dartvel build` and not
/// `dartvel doctor` shipped them, green.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVKioskTarget;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../doctor/kiosk_check.dart';
import '../doctor/module_check.dart';

class DVDeclarationCheck {
  const DVDeclarationCheck({required this.ok, required this.lines});

  /// Whether the build may go ahead.
  final bool ok;

  /// What to print. Empty when there is nothing declared to check.
  final List<String> lines;

  /// Reads what the project at [root] declares and decides whether a build
  /// of it can honour it.
  ///
  /// Targets are not passed: what is checked here is the half of the
  /// declaration that is wrong everywhere, so that the answer does not
  /// depend on which platform is being built. Per-target enforcement is
  /// `dartvel doctor`'s, which knows the targets.
  static DVDeclarationCheck run(String root) {
    Object? dartvel;
    final File pubspec = File(p.join(root, 'pubspec.yaml'));
    try {
      final Object? loaded = loadYaml(pubspec.readAsStringSync());
      dartvel = loaded is Map ? loaded['dartvel'] : null;
    } on Object {
      // The build has its own reading of the pubspec and its own message for
      // one it cannot read. A second, differently worded failure from here
      // would send somebody looking in the wrong place.
      return const DVDeclarationCheck(ok: true, lines: <String>[]);
    }

    final List<String> lines = <String>[];
    var ok = true;

    final DVKioskCheck kiosk =
        DVKioskCheck.run(dartvel, const <DVKioskTarget>[], root: root);
    if (!kiosk.ok) {
      lines.addAll(kiosk.lines);
      ok = false;
    }

    final DVModuleCheck modules = DVModuleCheck.run(root);
    if (!modules.ok) {
      lines.addAll(modules.lines);
      ok = false;
    }

    return DVDeclarationCheck(ok: ok, lines: lines);
  }
}
