// main.dart is the smallest entry Dartvel can boot today.
//
// The spec's entry is `void main(List<String> args) => DV.run(args);`, with
// the root declared in an @DVAppRoot. Neither is built yet (Application
// Entry is Designed in docs/spec-status.json), so the site calls the DV.run
// that exists, with its root kept out of main.dart -- and never runApp,
// which is Flutter's entry rather than Dartvel's.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main.dart is one DV.run call and nothing else', () {
    final List<String> code = File('lib/main.dart')
        .readAsLinesSync()
        .map((String l) => l.trim())
        .where((String l) =>
            l.isNotEmpty && !l.startsWith('//') && !l.startsWith('import '))
        .toList();
    expect(code, <String>['void main() => DV.run(createDartvelApp());']);
  });
}
