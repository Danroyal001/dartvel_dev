import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The Dart SDK version running this process, without the build date or
/// platform that [Platform.version] also carries.
String dartSdkVersion() => Platform.version.split(' ').first;

/// Which build of [package] this process is running: its pubspec version,
/// whether it came from the pub cache (`hosted`) or a path override (`path`),
/// and for a path checkout its git revision when one can be read.
///
/// Used so that every dump names exactly which original produced it.
Future<Map<String, Object?>> packageVersion(String package) async {
  final uri = await Isolate.resolvePackageUri(Uri.parse('package:$package/'));
  if (uri == null) {
    return {'version': 'unknown', 'source': 'unknown', 'revision': null};
  }
  final root = p.dirname(p.normalize(uri.toFilePath()));
  String version = 'unknown';
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (pubspec.existsSync()) {
    final yaml = loadYaml(pubspec.readAsStringSync());
    if (yaml is YamlMap && yaml['version'] != null) {
      version = '${yaml['version']}';
    }
  }
  final hosted = p.split(root).contains('hosted');
  String? revision;
  if (!hosted) {
    try {
      final result = await Process.run('git', [
        '-C',
        root,
        'rev-parse',
        'HEAD',
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode == 0) revision = '${result.stdout}'.trim();
    } on Object {
      revision = null;
    }
  }
  return {
    'version': version,
    'source': hosted ? 'hosted' : 'path',
    'revision': revision,
  };
}
