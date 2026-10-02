import 'dart:io';

import 'package:dartvel_cli/src/agents/architecture_docs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `docs/architecture/` in a project: written once, refreshed inside Dartvel's
/// block only, and quiet when nothing changed.
void main() {
  late Directory project;
  setUp(() => project = Directory.systemTemp.createTempSync('dartvel_architecture_docs_'));
  tearDown(() => project.deleteSync(recursive: true));

  File doc(String name) => File(p.join(project.path, 'docs', 'architecture', name));

  test('a first sync writes every section inside the markers', () async {
    final DVArchitectureDocsSyncResult result = await dvSyncArchitectureDocs(root: project.path);
    expect(result.created, hasLength(dvArchitectureDocSections().length));
    final String data = doc('data.md').readAsStringSync();
    expect(data, startsWith(dvArchitectureBlockBegin));
    expect(data, contains('importCsv'));
    expect(data, isNot(contains('Article.import(')));
  });

  test('a second sync with nothing changed writes nothing and says nothing', () async {
    await dvSyncArchitectureDocs(root: project.path);
    final DateTime before = doc('data.md').lastModifiedSync();
    final DVArchitectureDocsSyncResult again = await dvSyncArchitectureDocs(root: project.path);
    expect(again.isQuiet, isTrue);
    expect(doc('data.md').lastModifiedSync(), before);
  });

  test("a team's own notes around the block survive a refresh", () async {
    await dvSyncArchitectureDocs(root: project.path);
    final File data = doc('data.md');
    data.writeAsStringSync('# Our data rules\nOrders are never deleted.\n\n${data.readAsStringSync()}\nAppendix: ours.\n');
    final String edited = data.readAsStringSync();
    data.writeAsStringSync(edited.replaceFirst('importCsv', 'importSTALE'));
    final DVArchitectureDocsSyncResult result = await dvSyncArchitectureDocs(root: project.path);
    final String refreshed = data.readAsStringSync();
    expect(result.updated, <String>['docs/architecture/data.md']);
    expect(refreshed, contains('Orders are never deleted.'));
    expect(refreshed, contains('Appendix: ours.'));
    expect(refreshed, contains('importCsv'));
    expect(refreshed, isNot(contains('importSTALE')));
  });

  test('a file without markers keeps its text and gains the block below it', () {
    final String merged = dvMergeArchitectureBlock('# Ours\nKeep me.\n', '# Data\n\nbody');
    expect(merged, startsWith('# Ours\nKeep me.'));
    expect(merged, contains('$dvArchitectureBlockBegin\n# Data'));
  });

  test("none of this server's private rules leak into a user's project", () {
    for (final DVArchitectureDocSection section in dvArchitectureDocSections()) {
      expect(section.body, isNot(contains('heavy.sh')), reason: section.filename);
      expect(section.body, isNot(contains('brief')), reason: section.filename);
    }
  });
}
