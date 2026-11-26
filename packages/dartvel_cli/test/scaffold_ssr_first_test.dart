// A new project is SSR-first (on by default since 3.47.11), and its pubspec
// says, commented out, how to turn it off.
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('a new web project is SSR-first, and uncommenting the note in its pubspec turns it off', () {
    final String pubspec = ProjectTemplates.pubspecTemplate(name: 'probe', org: 'dev.dartvel');
    expect(pubspec, contains(dvScaffoldSsrFirstNote));
    // No web: key of its own, so a project can add one.
    expect(((loadYaml(pubspec) as Map)['dartvel'] as Map).containsKey('web'), isFalse);
    final Directory root = Directory.systemTemp.createTempSync('dv_scaffold_ssr_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
    expect(DVSplash.of(root.path).ssrFirst, isTrue);
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec
        .replaceFirst('  # web:\n', '  web:\n')
        .replaceFirst('  #   ssrFirst: false\n', '    ssrFirst: false\n'));
    expect(DVSplash.of(root.path).ssrFirst, isFalse, reason: 'the note, uncommented, turns it off');
  });

  test('a project with no web target carries no note', () {
    final String pubspec = ProjectTemplates.pubspecTemplate(name: 'probe', org: 'dev.dartvel', web: false);
    expect(pubspec, isNot(contains('ssrFirst')));
  });
}
