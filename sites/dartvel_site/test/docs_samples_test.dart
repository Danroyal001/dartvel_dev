// The code on the docs pages is code that compiled.
//
// Each sample lives in examples/docs_samples, where CI generates the client,
// analyzes the project and runs its tests. The site holds a copy because a
// web page cannot read the repository. These tests keep the copy honest in
// both directions: it matches the project, every sample a page names exists,
// and no sample sits in the project unused.
import 'dart:io';

import 'package:dartvel_site/components/docs_samples.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/docs_samples.dart';

void main() {
  test('the copy matches examples/docs_samples', () {
    final String expected =
        docsSamplesSource(readDocsSamples(Directory(kDocsSamplesProject)));
    expect(File(kDocsSamplesOutput).readAsStringSync(), expected,
        reason: 'Run: dart run tool/docs_samples.dart');
  });

  final Map<String, String> pages = <String, String>{
    for (final FileSystemEntity e
        in Directory('lib/pages/docs').listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e.path: e.readAsStringSync(),
  };
  final RegExp named = RegExp(r"Docs(?:Code|Yaml)\('([a-z0-9-]+)'\)");

  test('every sample a page names exists', () {
    final List<String> missing = <String>[
      for (final MapEntry<String, String> page in pages.entries)
        for (final Match m in named.allMatches(page.value))
          if (!kDocsSamples.containsKey(m[1])) '${page.key}: ${m[1]}',
    ];
    expect(missing, isEmpty);
  });

  test('every sample is shown on a page', () {
    final Set<String> used = <String>{
      for (final String source in pages.values)
        for (final Match m in named.allMatches(source)) m[1]!,
    };
    expect(kDocsSamples.keys.where((String k) => !used.contains(k)), isEmpty,
        reason: 'a sample nobody shows is code nothing checks against a page');
  });

  test('the reader finds regions and refuses a broken one', () {
    final Directory dir = Directory.systemTemp.createTempSync('docs_samples_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/lib').createSync();
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
    File('${dir.path}/lib/a.dart').writeAsStringSync('''
void f() {
  // docs:start one
  final int a = 1;
    print(a);
  // docs:end
}
''');
    expect(readDocsSamples(dir), <String, List<String>>{
      'one': <String>['final int a = 1;', '  print(a);'],
    });
    File('${dir.path}/lib/b.dart').writeAsStringSync('// docs:start two\n');
    expect(() => readDocsSamples(dir), throwsStateError);
  });
}
