import 'dart:io';

import 'package:dartvel_cli/src/build/semantics_capture.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('a guarded route\'s old capture is deleted; the others are kept', () {
    final Directory root = Directory.systemTemp.createTempSync('dv_forget_');
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory dir = Directory(p.join(root.path, '.dart_tool', 'dartvel_semantics'))
      ..createSync(recursive: true);
    for (final String name in <String>['index', 'index.images', 'about', 'account_settings']) {
      File(p.join(dir.path, '$name.json')).writeAsStringSync('[]');
    }
    final List<String> removed =
        dvForgetGuardedCaptures(root.path, <String>{'/', '/account/settings'});
    expect(removed, hasLength(3));
    expect(File(p.join(dir.path, 'index.json')).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'index.images.json')).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'account_settings.json')).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'about.json')).existsSync(), isTrue);
  });
}
