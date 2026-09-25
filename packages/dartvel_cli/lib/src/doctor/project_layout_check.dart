/// `dartvel doctor`'s report of where a project keeps its sources.
///
/// Every directory here is optional. An application never carries a subsystem
/// it did not use, so a project with no models or no backend functions is a
/// whole project: an absent directory is reported with `[-]`, as information,
/// never with the `[!]` that means something needs fixing. The directories
/// are the ones the project configured (`pagesDir`, `backendDir`,
/// `modelsDir`), not the defaults.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class DVProjectLayoutCheck {
  const DVProjectLayoutCheck({required this.lines});

  final List<String> lines;

  static DVProjectLayoutCheck run({
    required String root,
    required String pagesDir,
    required String modelsDir,
    required String backendDir,
  }) {
    final List<(String, String)> dirs = <(String, String)>[
      (pagesDir, 'no file routes; routes can still be declared in code'),
      (p.posix.join(backendDir, 'functions'), 'no backend functions'),
      (modelsDir, 'no models'),
    ];
    return DVProjectLayoutCheck(
      lines: <String>[
        for (final (String dir, String absent) in dirs)
          Directory(p.join(root, dir)).existsSync()
              ? '[+] $dir exists'
              : '[-] $dir not present ($absent)',
      ],
    );
  }
}
