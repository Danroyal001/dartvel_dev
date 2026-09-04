/// Writes `dist/latest.json`: every platform this release actually carries.
///
///     dart run tool/ci/release_manifest.dart <version> > dist/latest.json
///
/// The npm launcher and the Homebrew tap read it to resolve a URL rather than
/// constructing one and hoping. A binary that was not built is absent from
/// this file, which is the difference between an installer that says so and
/// one that downloads a 404.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

/// The verdict, as an exit code. Returned rather than exited on so the
/// whole of it is one function with one way out.
int _run(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: release_manifest.dart <version>');
    return 2;
  }
  final String version = arguments.single;
  const String repository = 'https://github.com/Danroyal001/dartvel_dev';
  final String base = '$repository/releases/download/v$version';

  // The digests the step has already written, rather than computed again
  // here: one answer, from the file the release publishes, so the manifest
  // and SHA256SUMS cannot disagree about the same binary.
  final File sums = File('dist/SHA256SUMS');
  if (!sums.existsSync()) {
    stderr.writeln('dist/SHA256SUMS is not there; nothing to describe.');
    return 1;
  }
  final Map<String, Object?> assets = <String, Object?>{};
  // By name, not by digest: the file is written in whatever order the shell
  // listed it and a manifest that reorders itself between releases is a diff
  // nobody can read.
  final List<String> lines = sums.readAsLinesSync()
    ..sort((String a, String b) => _nameOf(a).compareTo(_nameOf(b)));
  for (final String line in lines) {
    final int gap = line.indexOf(' ');
    if (gap < 0) continue;
    final String digest = line.substring(0, gap).trim();
    final String name = line.substring(gap).trim().replaceFirst('*', '');
    if (name.isEmpty || name == 'SHA256SUMS' || name == 'latest.json') continue;
    assets[name] = <String, Object?>{
      'url': '$base/$name',
      'sha256': digest,
    };
  }

  stdout.write(const JsonEncoder.withIndent('  ')
      .convert(<String, Object?>{'version': version, 'assets': assets}));
  return 0;
}

/// The filename half of a `sha256sum` line.
String _nameOf(String line) {
  final int gap = line.indexOf(' ');
  return gap < 0 ? line : line.substring(gap).trim().replaceFirst('*', '');
}
