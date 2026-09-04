/// Writes and checks a webOS `appinfo.json`.
///
///     dart tool/ci/webos_appinfo.dart write <dir>
///     dart tool/ci/webos_appinfo.dart check <dir>
///
/// The checks are the ones webOS reports only as a generic install failure on
/// the television, hours after the build that caused them: an id that is not
/// reverse-DNS or not lowercase, a type that is not native, a version that is
/// not three numeric parts.
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  exitCode = _run(arguments);
}

int _run(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('usage: webos_appinfo.dart <write|check> <dir>');
    return 2;
  }
  final File file = File('${arguments[1]}/appinfo.json');
  switch (arguments.first) {
    case 'write':
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(const JsonEncoder.withIndent('  ')
          .convert(<String, Object?>{
        'id': 'com.dartvel.example',
        'title': 'Dartvel Example',
        'version': '1.0.0',
        'type': 'native',
        'main': 'dartvel_app',
        'icon': 'icon.png',
        'vendor': 'Dartvel',
      }));
      return 0;
    case 'check':
      if (!file.existsSync()) {
        stdout.writeln('::error::${file.path} is not there');
        return 1;
      }
      final Object? decoded = jsonDecode(file.readAsStringSync());
      final Map<String, Object?> info =
          decoded is Map<String, Object?> ? decoded : const <String, Object?>{};
      final String id = '${info['id'] ?? ''}';
      final String version = '${info['version'] ?? ''}';
      final List<String> problems = <String>[
        if (!id.contains('.')) 'id is not reverse-DNS',
        if (id != id.toLowerCase()) 'id is not lowercase',
        if (info['type'] != 'native') 'type is not native',
        if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version))
          'version is not three numeric parts',
      ];
      if (problems.isNotEmpty) {
        stdout.writeln('::error::${problems.join('; ')}');
        return 1;
      }
      stdout.writeln('appinfo.json is acceptable: $id $version');
      return 0;
    default:
      stderr.writeln('usage: webos_appinfo.dart <write|check> <dir>');
      return 2;
  }
}
