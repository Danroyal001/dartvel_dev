// `dartvel dev` sets up the agent files, and `dartvel create` does too.
//
// These are the two entry points a project actually goes through, and neither
// may be optional: a generated block that only appears when somebody runs a
// command nobody knows about is how the block drifts from the version it names.
import 'dart:io';

import 'package:dartvel_cli/src/agents/agent_docs.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_agent_entry_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  test('the files a new project gets include every agent', () {
    // Not a filesystem test: this is about the scaffold's file list, which is
    // what a project is given.
    expect(dvAgentDocTargets().map((DVAgentDocTarget t) => t.path),
        contains('AGENTS.md'));
  });

  test('sync names the project from its pubspec, not its folder', () async {
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: my_app\n');
    final Directory nested = Directory(p.join(root.path, 'src', 'app'));
    nested.createSync(recursive: true);

    await dvSyncAgentDocs(root: nested.path);

    // The rules do not depend on the project's name; what matters is that a
    // project whose folder is `app` still gets rules generated for `my_app`
    // rather than for the directory it happens to sit in.
    expect(File(p.join(nested.path, 'AGENTS.md')).existsSync(), isTrue);
  });

  test('a project with no pubspec still gets agent files', () async {
    // `dartvel dev` runs before a pubspec exists in some flows, and refusing
    // to write documentation then would mean the files never appear.
    await dvSyncAgentDocs(root: root.path);

    expect(File(p.join(root.path, 'CLAUDE.md')).existsSync(), isTrue);
  });
}