/// Fails when a package this repository pins has a known vulnerability.
///
///     dart tool/ci/dependency_advisories_check.dart
///
/// Every tracked `pubspec.lock`, every hosted package in it, asked of OSV in
/// one batch per file. How it reads a lock file and why it refuses a short
/// answer is in `tool/ci/dependency_advisories.dart`.
///
/// It needs the network. A run that cannot reach OSV fails rather than
/// passing quietly: "nothing reported" and "nobody was asked" are the same
/// output otherwise, which is the failure this check was added to stop.
library;

import 'dart:io';

import 'dependency_advisories.dart';

Future<void> main(List<String> arguments) async {
  final Map<String, Map<String, String>> byFile = dvRepositoryPackages();
  if (byFile.isEmpty) {
    // Lock files are gitignored, so a fresh checkout has none until something
    // resolves. Refusing here rather than reporting a clean scan is the
    // difference this check exists for, and its first run needed it.
    stdout.writeln('::error::no pubspec.lock was found to check. Resolve '
        'first: flutter pub get in each package, which is what '
        '.github/workflows/dependencies.yml does.');
    exitCode = 1;
    return;
  }

  final List<DVAdvisory> found = <DVAdvisory>[];
  int packages = 0;
  for (final MapEntry<String, Map<String, String>> entry in byFile.entries) {
    packages += entry.value.length;
    try {
      found.addAll(await dvQueryOsv(entry.value, file: entry.key));
    } on Object catch (error) {
      stdout.writeln('::error::${entry.key}: $error');
      exitCode = 1;
      return;
    }
  }

  stdout.writeln('${byFile.length} lock file(s), $packages pinned package(s) '
      'asked of OSV.');

  if (found.isEmpty) {
    stdout.writeln('no known advisories');
    return;
  }

  // Grouped by package rather than by file: the same version is usually
  // pinned in several lock files, and one upgrade fixes all of them.
  final Map<String, DVAdvisory> unique = <String, DVAdvisory>{};
  final Map<String, Set<String>> files = <String, Set<String>>{};
  for (final DVAdvisory advisory in found) {
    final String key = '${advisory.package} ${advisory.version}';
    unique[key] = advisory;
    (files[key] ??= <String>{}).add(advisory.file);
  }

  for (final MapEntry<String, DVAdvisory> entry in unique.entries) {
    final DVAdvisory advisory = entry.value;
    stdout.writeln('::error::${advisory.package} ${advisory.version} '
        '(${files[entry.key]!.join(', ')}): ${advisory.ids.join(', ')} — '
        'https://osv.dev/vulnerability/${advisory.ids.first}');
  }
  stdout.writeln('${unique.length} package(s) with an advisory. '
      'Upgrade, or record why the advisory does not apply.');
  exitCode = 1;
}
