import 'dart:io';

import 'package:dartvel_cli/src/build/desktop_entry.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('two file types with equal icon basenames retain their own artwork', () {
    final root = Directory.systemTemp.createTempSync('dv_windows_type_icons');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: app
dartvel:
  fileAssociations:
    - mimeType: application/x-alpha
      extensions: [alpha]
      icon: assets/alpha/icon.ico
    - mimeType: application/x-beta
      extensions: [beta]
      icon: assets/beta/icon.ico
''');
    for (final name in ['alpha', 'beta']) {
      File(p.join(root.path, 'assets', name, 'icon.ico'))
        ..createSync(recursive: true)
        ..writeAsStringSync(name);
    }
    final bundle = Directory(p.join(root.path, 'bundle'))..createSync();
    final result = dvWriteWindowsDesktopFiles(root.path, bundle.path);
    expect(result.problems, isEmpty);
    final icons = result.written
        .where((path) => path.endsWith('.ico'))
        .toList();
    expect(icons.toSet(), hasLength(2));
    expect(
      icons
          .map((name) => File(p.join(bundle.path, name)).readAsStringSync())
          .toSet(),
      {'alpha', 'beta'},
    );
    final script = File(p.join(bundle.path, 'app-associations.reg'))
        .readAsStringSync();
    for (final icon in icons) {
      expect(script, contains(icon));
    }
  });
}
