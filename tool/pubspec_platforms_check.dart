// Every published package declares the platforms it runs on.
//
//   dart run tool/pubspec_platforms_check.dart
//
// pub.dev infers a package's platforms from its import graph, and the
// inference follows imports that only run on one platform. dartvel_flutter
// imports package:dbus for the Linux tray and package:jni for the Android
// keystore, each reached only on its own platform at run time, and pub.dev
// listed the whole package as Linux and Windows only. dartvel_core has a web
// worker entry point and a dart:io payload reader, and was listed as
// supporting nothing at all.
//
// The pubspec's `platforms:` field is what pub.dev shows instead of the
// inference, so each published package says what it supports here, and this
// keeps the declaration matching what Dartvel ships for.
//
// Exits non-zero and prints every problem rather than the first.
import 'dart:io';

const List<String> _everywhere = <String>[
  'android',
  'ios',
  'linux',
  'macos',
  'web',
  'windows',
];

/// What each published package runs on. The CLI and the generator run where
/// a developer builds, which is a desktop; everything an application imports
/// runs wherever the application does.
const Map<String, List<String>> _expected = <String, List<String>>{
  'dartvel_core': _everywhere,
  'dartvel_flutter': _everywhere,
  'dartvel_dev': _everywhere,
  'dartvel_shelf': _everywhere,
  'dartvel_cli': <String>['linux', 'macos', 'windows'],
  'dartvel_generator': <String>['linux', 'macos', 'windows'],
};

void main(List<String> arguments) {
  final Directory packages = Directory('${_repoRoot().path}/packages');
  final List<String> problems = <String>[];
  final Set<String> seen = <String>{};

  for (final Directory dir in packages.listSync().whereType<Directory>()) {
    final File pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final List<String> lines = pubspec.readAsLinesSync();
    final String name = lines
        .firstWhere((String l) => l.startsWith('name:'))
        .substring('name:'.length)
        .trim();
    if (lines.any((String l) => RegExp(r'^publish_to:\s*none').hasMatch(l))) {
      continue;
    }
    seen.add(name);
    final List<String>? want = _expected[name];
    if (want == null) {
      problems.add('$name is published but not listed in tool/pubspec_platforms_check.dart. '
          'Add it with the platforms it runs on.');
      continue;
    }
    final List<String> declared = _declared(lines);
    if (declared.isEmpty) {
      problems.add('$name declares no platforms, so pub.dev infers them from '
          'imports. Add a top-level platforms: block with ${want.join(', ')}.');
    } else if (declared.join(',') != (List<String>.of(want)..sort()).join(',')) {
      problems.add('$name declares ${declared.join(', ')}; it runs on '
          '${want.join(', ')}.');
    }
  }

  for (final String name in _expected.keys) {
    if (!seen.contains(name)) {
      problems.add('$name is listed here but is not a published package.');
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }
  stdout.writeln('${seen.length} published packages declare their platforms.');
}

/// The keys under a top-level `platforms:` block, sorted.
List<String> _declared(List<String> lines) {
  final int start = lines.indexWhere((String l) => l.trimRight() == 'platforms:');
  if (start < 0) return const <String>[];
  final List<String> found = <String>[];
  for (final String line in lines.skip(start + 1)) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) break;
    found.add(line.trim().replaceAll(RegExp(r':.*$'), ''));
  }
  return found..sort();
}

Directory _repoRoot() {
  Directory dir = Directory.current;
  while (!File('${dir.path}/tool/pubspec_platforms_check.dart').existsSync()) {
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('run from inside the dartvel_dev repository');
    }
    dir = parent;
  }
  return dir;
}
