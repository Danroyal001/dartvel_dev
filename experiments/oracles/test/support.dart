import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes [files] (relative path -> contents) under a fresh temp directory
/// and returns its path.
String writeTree(Map<String, String> files, {String prefix = 'oracle_'}) {
  final dir = Directory.systemTemp.createTempSync(prefix).path;
  files.forEach((relative, contents) {
    final file = File(p.joinAll([dir, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return dir;
}

/// Every file under [dir], as `relative path -> bytes`, sorted by path.
Map<String, List<int>> readTree(String dir) {
  final entries = <String, List<int>>{};
  for (final entity in Directory(dir).listSync(recursive: true)) {
    if (entity is File) {
      final relative = p.split(p.relative(entity.path, from: dir)).join('/');
      entries[relative] = entity.readAsBytesSync();
    }
  }
  final keys = entries.keys.toList()..sort();
  return {for (final k in keys) k: entries[k]!};
}

String tempOut() => Directory.systemTemp.createTempSync('oracle_out_').path;

/// A small package corpus: a pubspec declaring a language version, a file
/// the formatter changes, a file that does not parse, and a file with a
/// known analyzer diagnostic.
Map<String, String> samplePackage() => {
  'pubspec.yaml': 'name: sample\nenvironment:\n  sdk: ^3.13.0\n',
  'lib/a.dart': 'void main( ){print( 1 );}\n',
  'lib/src/b.dart': 'int f(int x)=>x+1;\n',
  'lib/broken.dart': 'void main( { \n',
  'lib/unused.dart':
      "import 'dart:async';\n\nint g() {\n  int unused = 1;\n  return 2;\n}\n",
};
