/// Checks a browser extension manifest before a browser is asked to load it.
///
///     dart tool/ci/manifest_check.dart mv3 <manifest.json>
///     dart tool/ci/manifest_check.dart firefox <manifest.json> [id-file]
///
/// Both browsers report these as a generic "could not load extension", which
/// is the same message they give for a missing file — so the manifest is
/// read here, where the problem can be named.
///
/// The Firefox form also writes the add-on id out, because the step that
/// installs it has to put the same id in the profile.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  if (arguments.length < 2) {
    stderr.writeln('usage: manifest_check.dart <mv3|firefox> <manifest.json>');
    return 2;
  }
  final File file = File(arguments[1]);
  if (!file.existsSync()) {
    stdout.writeln('::error::${file.path} is not there');
    return 1;
  }
  final Object? decoded = jsonDecode(file.readAsStringSync());
  final Map<String, Object?> manifest =
      decoded is Map<String, Object?> ? decoded : const <String, Object?>{};

  final List<String> problems = <String>[];
  if (manifest['manifest_version'] != 3) {
    problems.add('manifest_version is ${manifest['manifest_version']}, not 3');
  }

  switch (arguments.first) {
    case 'mv3':
      for (final String required in const <String>['name', 'version']) {
        final Object? value = manifest[required];
        if (value == null || '$value'.isEmpty) problems.add('missing $required');
      }
      final Object? background = manifest['background'];
      final Map<Object?, Object?> declared =
          background is Map ? background : const <Object?, Object?>{};
      if (!declared.containsKey('service_worker')) {
        problems.add('MV3 background must declare a service_worker');
      }
      if (problems.isNotEmpty) {
        stdout.writeln('manifest problems: ${problems.join('; ')}');
        return 1;
      }
      stdout.writeln('manifest_version 3, ${manifest['name']} '
          '${manifest['version']}');
      return 0;
    case 'firefox':
      final Object? settings = manifest['browser_specific_settings'];
      final Object? gecko = settings is Map ? settings['gecko'] : null;
      final Map<Object?, Object?> geckoSettings =
          gecko is Map ? gecko : const <Object?, Object?>{};
      final String id = '${geckoSettings['id'] ?? ''}';
      if (id.isEmpty) problems.add('the Firefox manifest names no add-on id');
      if (problems.isNotEmpty) {
        stdout.writeln('::error::${problems.join('; ')}');
        return 1;
      }
      stdout.writeln('add-on id: $id');
      if (arguments.length > 2) File(arguments[2]).writeAsStringSync(id);
      return 0;
    default:
      stderr.writeln('usage: manifest_check.dart <mv3|firefox> <manifest.json>');
      return 2;
  }
}
