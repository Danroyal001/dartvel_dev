import 'dart:io';

import 'package:dartvel_cli/src/config/dartvel_section.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('a new config read observes edits in imported source', () {
    final root = Directory.systemTemp.createTempSync('dv_config_freshness');
    addTearDown(() => root.deleteSync(recursive: true));
    final core = p.normalize(p.absolute('..', 'dartvel_core'));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: config_fixture
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: $core
dartvel: config.dart
''');
    File(p.join(root.path, 'config.dart')).writeAsStringSync('''
import 'package:dartvel_core/config.dart';
import 'types.dart';
class const AppConfig() extends DartvelConfig {
  @override
  List<DVFileAssociation> get fileAssociations => [DVFileAssociation(mimeType: mime)];
}
''');
    final types = File(p.join(root.path, 'types.dart'));
    types.writeAsStringSync("const mime = 'text/plain';\n");
    final got = Process.runSync('dart', [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: root.path);
    expect(got.exitCode, 0, reason: '${got.stderr}');
    expect('${dvDartvelSection(root.path).values}', contains('text/plain'));
    types.writeAsStringSync("const mime = 'application/pdf';\n");
    expect(
      '${dvDartvelSection(root.path).values}',
      contains('application/pdf'),
    );
  });
}
