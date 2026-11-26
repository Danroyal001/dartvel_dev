// A new project is SSR-first (on by default since 3.47.11) and its pubspec
// says so where the reader can turn it off.
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('the scaffold pubspec carries dartvel.web.ssrFirst: true and the build reads it as on', () {
    final String pubspec = ProjectTemplates.pubspecTemplate(name: 'probe', org: 'dev.dartvel');
    final Object? document = loadYaml(pubspec);
    expect(((document as Map)['dartvel'] as Map)['web'], containsPair('ssrFirst', true));
    final Directory root = Directory.systemTemp.createTempSync('dv_scaffold_ssr_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
    expect(DVSplash.of(root.path).ssrFirst, isTrue);
    File(p.join(root.path, 'pubspec.yaml'))
        .writeAsStringSync(pubspec.replaceFirst('ssrFirst: true', 'ssrFirst: false'));
    expect(DVSplash.of(root.path).ssrFirst, isFalse, reason: 'false in the scaffold turns it off');
  });
}
