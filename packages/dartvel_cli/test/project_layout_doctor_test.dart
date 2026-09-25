// `dartvel doctor` on a project's source layout.
//
// An application never carries a subsystem it did not use, so a project with
// no models, or no backend, is a whole project rather than a broken one. The
// check printed `[!] lib/models missing` for exactly that project and then
// said "All system checks passed!" underneath it: a warning nothing was wrong
// enough to fail on, which teaches the reader to ignore the `[!]` that is.
//
// It also looked in lib/pages, lib/backend/functions and lib/models whatever
// the project's `pagesDir`, `backendDir` and `modelsDir` said, so a project
// that had moved its pages was told they were missing.
import 'dart:io';

import 'package:dartvel_cli/src/doctor/project_layout_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dv_layout_'));
  tearDown(() => root.deleteSync(recursive: true));

  void mkdir(String relative) =>
      Directory(p.join(root.path, relative)).createSync(recursive: true);

  DVProjectLayoutCheck check({
    String pagesDir = 'lib/pages',
    String modelsDir = 'lib/models',
    String backendDir = 'lib/backend',
  }) => DVProjectLayoutCheck.run(
    root: root.path,
    pagesDir: pagesDir,
    modelsDir: modelsDir,
    backendDir: backendDir,
  );

  test('a project without models is not warned about', () {
    mkdir('lib/pages');
    mkdir('lib/backend/functions');

    final DVProjectLayoutCheck result = check();

    expect(result.lines.where((String l) => l.startsWith('[!]')), isEmpty);
    expect(result.lines.join('\n'), contains('[-] lib/models'));
  });

  test('a project with only pages is whole', () {
    mkdir('lib/pages');

    final DVProjectLayoutCheck result = check();

    expect(result.lines.where((String l) => l.startsWith('[!]')), isEmpty);
    expect(result.lines.join('\n'), contains('[+] lib/pages'));
  });

  test('the directories are the ones the project configured', () {
    mkdir('lib/screens');
    mkdir('lib/server/functions');
    mkdir('lib/data');

    final DVProjectLayoutCheck result = check(
      pagesDir: 'lib/screens',
      modelsDir: 'lib/data',
      backendDir: 'lib/server',
    );

    final String out = result.lines.join('\n');
    expect(out, contains('[+] lib/screens'));
    expect(out, contains('[+] lib/server/functions'));
    expect(out, contains('[+] lib/data'));
    expect(out, isNot(contains('lib/pages')));
    expect(out, isNot(contains('lib/models')));
  });

  test('what exists is still reported as present', () {
    mkdir('lib/pages');
    mkdir('lib/models');
    mkdir('lib/backend/functions');

    final List<String> lines = check().lines;

    expect(lines, <String>[
      '[+] lib/pages exists',
      '[+] lib/backend/functions exists',
      '[+] lib/models exists',
    ]);
  });
}
