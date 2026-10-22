import 'dart:io';

import 'package:test/test.dart';

/// The files a web build compiles: the public library and everything it
/// reaches, with the conditional import taking its web side.
const List<String> webCompiled = <String>[
  'lib/dartvel_documents.dart',
  'lib/src/documents.dart',
  'lib/src/document_page.dart',
  'lib/src/pdfium_release.dart',
  'lib/src/documents_backend_web.dart',
];

void main() {
  test('nothing a web build compiles imports dart:ffi or dart:io', () {
    for (final String path in webCompiled) {
      final List<String> imports = File(path)
          .readAsLinesSync()
          .where((String line) => line.startsWith('import ') || line.startsWith('export '))
          .toList();
      // The one conditional import names the FFI backend only for dart.library.ffi.
      final List<String> unconditional = imports.where((String line) => !line.contains(' if (dart.library.')).toList();
      expect(unconditional.where((String line) => line.contains("'dart:ffi'") || line.contains("'dart:io'")), isEmpty,
          reason: path);
      expect(unconditional.where((String line) => line.contains('backend_ffi') || line.contains('pdfium_ffi')), isEmpty,
          reason: '$path reaches the FFI backend unconditionally');
    }
  });

  test('the public library reaches only web-safe files', () {
    final Set<String> reached = <String>{};
    void visit(String path) {
      if (!reached.add(path)) return;
      for (final String line in File(path).readAsLinesSync()) {
        final Match? m = RegExp(r"^(?:import|export) '([^']+\.dart)'").firstMatch(line);
        if (m == null || line.contains(' if (dart.library.')) continue;
        final String target = m.group(1)!;
        if (target.startsWith('package:') || target.startsWith('dart:')) continue;
        visit(File(path).parent.uri.resolve(target).toFilePath().replaceFirst('${Directory.current.path}/', ''));
      }
    }

    visit('lib/dartvel_documents.dart');
    for (final String path in reached) {
      expect(webCompiled, contains(path), reason: '$path is reached by the public library; is it web-safe?');
    }
  });
}
