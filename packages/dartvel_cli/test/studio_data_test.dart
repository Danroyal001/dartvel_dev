// What a build keeps for Studio: data, never a page.
//
// Studio used to arrive as a static dashboard -- index.html, a stylesheet, a
// script -- and later as a second Flutter application, both files under the
// mount. Studio is now routes of the application, so a build keeps only what
// Studio reads through its API: the project graph, and each page's captured
// structure. Nothing here is a document, and nothing is ever served as a file.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/studio_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('is the project graph, exactly as it came in, and no page', () {
    final Map<String, Object?> graph = <String, Object?>{
      'models': <Object?>[
        <String, Object?>{'name': 'Note', 'source': 'lib/models/note.dart'},
      ],
      'jobs': <Object?>[],
    };
    final Map<String, String> files = dvStudioData(graph: graph);
    expect(files.keys, <String>['graph.json']);
    expect(jsonDecode(files['graph.json']!), graph);
  });

  test("copies each page's structure, and nothing an earlier build left", () {
    final Directory root = Directory.systemTemp.createTempSync('dv_studio_data_');
    addTearDown(() => root.deleteSync(recursive: true));
    final String semantics = p.join(root.path, 'semantics');
    final String data = p.join(root.path, 'data');
    File(p.join(semantics, 'index.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"route":"/"}');
    File(p.join(semantics, 'index.images.json')).writeAsStringSync('[]');
    File(p.join(data, 'structure', 'gone.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');

    expect(dvCopyPageStructures(semantics: semantics, adminRoot: data), 1);
    expect(
        Directory(p.join(data, 'structure'))
            .listSync()
            .map((FileSystemEntity e) => p.basename(e.path)),
        <String>['index.json']);
  });
}
