// What a plain Dart package offers a module: its public functions, the ones
// every environment can call, and the ones it cannot with the reason.
//
// Read from the package's own library and the files it exports, since the
// wrapper forwards to exactly those. The failures worth testing are the
// quiet ones: a private helper exposed, a function from a hidden export
// exposed, a string holding a brace read as structure, a parameter that is
// a callback forwarded as if it were a value.
import 'dart:io';

import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory package(Map<String, String> files, {String name = 'textkit'}) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_surface_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(p.join(dir.path, 'pubspec.yaml'))
      .writeAsStringSync('name: $name\nversion: 1.2.3\n');
  for (final MapEntry<String, String> f in files.entries) {
    File(p.join(dir.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  return dir;
}

void main() {
  test('public top-level functions become operations, with their signatures',
      () {
    final DVDartSurface surface = dvScanDartPackage(package(<String, String>{
      'lib/textkit.dart': r'''
library textkit;

/// Turns [text] into a slug.
String slug(String text, {String separator = '-', int? maxLength}) {
  return text.toLowerCase().replaceAll(' ', separator);
}

int _hidden() => 1;

Future<List<String>> words(String text, [bool unique = false]) async =>
    text.split(' ');

String get version => '1';

class Tokenizer {
  String split(String a) { return a; }
}

const String brace = '{ not a body; }';

bool isBlank(String? text) => text == null || text.trim().isEmpty;
''',
    }).path);

    expect(surface.packageName, 'textkit');
    expect(surface.version, '1.2.3');
    expect(surface.operations.map((DVModuleOperation o) => o.name),
        <String>['isBlank', 'slug', 'words']);
    final DVModuleOperation slug =
        surface.operations.firstWhere((DVModuleOperation o) => o.name == 'slug');
    expect(slug.returnType, 'String');
    expect(slug.doc, contains('Turns [text] into a slug.'));
    expect(slug.parameterList,
        "String text, {String separator = '-', int? maxLength}");
    expect(slug.argumentList,
        'text, separator: separator, maxLength: maxLength');
    final DVModuleOperation words = surface.operations
        .firstWhere((DVModuleOperation o) => o.name == 'words');
    expect(words.isAsync, isTrue);
    expect(words.parameterList, 'String text, [bool unique = false]');
  });

  test('exports are followed, and show and hide are honoured', () {
    final DVDartSurface surface = dvScanDartPackage(package(<String, String>{
      'lib/textkit.dart': "export 'src/a.dart' show shout;\n"
          "export 'src/b.dart' hide secret;\n",
      'lib/src/a.dart': 'String shout(String s) => s.toUpperCase();\n'
          'String whisper(String s) => s.toLowerCase();\n',
      'lib/src/b.dart': 'int count(String s) => s.length;\n'
          'int secret() => 42;\n',
    }).path);
    expect(surface.operations.map((DVModuleOperation o) => o.name),
        <String>['count', 'shout']);
  });

  test('what cannot cross every environment is left out, with the reason',
      () {
    final DVDartSurface surface = dvScanDartPackage(package(<String, String>{
      'lib/textkit.dart': '''
class Token { const Token(); }
Token first(String s) => const Token();
T pick<T>(List<T> items) => items.first;
void each(List<String> items, void Function(String) visit) {}
String pad(String s, {int width = defaultWidth}) => s;
const int defaultWidth = 4;
''',
    }).path);
    expect(surface.operations, isEmpty);
    expect(surface.skipped['first'], contains('Token'));
    expect(surface.skipped['pick'], 'is generic');
    expect(surface.skipped['each'], contains('function'));
    expect(surface.skipped['pad'], contains('not a literal'));
  });

  test('what the package needs from a platform is read from its imports', () {
    DVDartPlatformNeeds needs(String code) => dvScanDartPackage(
            package(<String, String>{'lib/textkit.dart': code}).path)
        .needs;

    final DVDartPlatformNeeds pure = needs('String a() => "";');
    expect((pure.native, pure.web, pure.backend), (true, true, true));

    final DVDartPlatformNeeds io =
        needs("import 'dart:io';\nString a() => Platform.pathSeparator;");
    expect((io.native, io.web, io.backend), (true, false, true));

    final DVDartPlatformNeeds flutter = needs(
        "import 'package:flutter/widgets.dart';\nString a() => '';");
    expect((flutter.native, flutter.web, flutter.backend), (true, true, false));

    final DVDartPlatformNeeds browser =
        needs("import 'package:web/web.dart';\nString a() => '';");
    expect((browser.native, browser.web, browser.backend), (false, true, false));

    // A conditional import is the package arranging for each platform.
    final DVDartPlatformNeeds adaptive = needs(
        "import 'src/stub.dart' if (dart.library.io) 'dart:io';\nString a() => '';");
    expect((adaptive.native, adaptive.web, adaptive.backend), (true, true, true));
  });

  test('a package with no library of its own name has no surface', () {
    expect(
      () => dvScanDartPackage(package(<String, String>{'lib/other.dart': ''}).path),
      throwsA(isA<DVDartSurfaceRefused>().having(
          (DVDartSurfaceRefused e) => e.message, 'message', contains('DV-MODULE-010'))),
    );
  });
}
