import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../build/webos_package.dart';
import '../utils/logger.dart';

/// `dartvel webos verify-package` — proving an assembled package is one a
/// television could launch.
///
/// The build already validated appinfo.json, which is not the same thing. It
/// checked that `main` named something and never that the something existed,
/// so the example packaged and passed while pointing at a `dartvel_app` that
/// was never built. webOS reports that as an install failure naming no file,
/// hours after the build that caused it.
class WebosCommand extends Command<void> {
  @override
  final String name = 'webos';

  @override
  final String description = 'Inspect and verify assembled webOS packages.';

  WebosCommand() {
    addSubcommand(_VerifyPackageCommand());
  }
}

class _VerifyPackageCommand extends Command<void> {
  @override
  final String name = 'verify-package';

  @override
  final String description =
      'Fail unless the package holds everything appinfo.json names.';

  @override
  String get invocation => 'dartvel webos verify-package <package-directory>';

  @override
  void run() {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Give the package directory to verify.', invocation);
    }

    final dir = Directory(rest.first);
    if (!dir.existsSync()) {
      log('There is no package at ${dir.path}.');
      exit(1);
    }

    final appinfo = File(p.join(dir.path, 'appinfo.json'));
    if (!appinfo.existsSync()) {
      log('${dir.path} holds no appinfo.json, so it is not a package.');
      exit(1);
    }

    final Map<String, Object?> info =
        (jsonDecode(appinfo.readAsStringSync()) as Map).cast<String, Object?>();

    // Relative to the application root, which is how appinfo names things.
    final files = <String>{
      for (final FileSystemEntity e in dir.listSync(recursive: true))
        if (e is File) p.relative(e.path, from: dir.path),
    };

    final problems = <String>[
      ...webosPackageProblems(info),
      ...webosPackageContentProblems(info, files),
    ];

    if (problems.isEmpty) {
      log('${info['id']} ${info['version']}: a package webOS would '
          'accept, with ${files.length} files.');
      return;
    }

    for (final String problem in problems) {
      log(problem);
    }
    exit(1);
  }
}
