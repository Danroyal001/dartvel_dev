// The native HTTP transport uses dart:ffi, which the web target does not have,
// so it is exported conditionally with a web stand-in — the same arrangement
// the SQLite adapter already uses.
//
// This exists because the export was unconditional and broke the web build:
// `Dart library 'dart:ffi' is not available on this platform`. Nothing caught
// it, because nothing built web after the transport was added. The build is the
// real regression test; this one catches the quieter failure, which is the two
// files drifting apart until some name exists on native and not on web.
import 'dart:io';

import 'package:test/test.dart';

/// Top-level public declarations, by name.
///
/// Deliberately crude — it reads the source rather than reflecting, because the
/// whole point is to compare a file this VM cannot import against one it can.
Set<String> publicApiOf(String path) {
  final source = File(path).readAsStringSync();
  final names = <String>{};

  for (final match in RegExp(r'^(?:abstract\s+)?class\s+(\w+)', multiLine: true)
      .allMatches(source)) {
    names.add(match.group(1)!);
  }
  // Top-level functions: a return type, then a name, then an open paren — and
  // the line must begin with a non-space, which is what makes it top-level.
  //
  // The (?!\s) matters more than it looks. Without it the whitespace inside the
  // character class let the pattern match indented class members too, and the
  // test reported referenced types like DVHttpResponse as missing declarations.
  for (final match in RegExp(
          r'^(?!\s)[\w<>,\?]+(?:\s+[\w<>,\?]+)*\s+(\w+)\s*\(',
          multiLine: true)
      .allMatches(source)) {
    names.add(match.group(1)!);
  }
  names.removeWhere((String name) => name.startsWith('_'));
  return names;
}

void main() {
  const nativePath = 'lib/src/http/native_client.dart';
  const webPath = 'lib/src/http/native_client_web.dart';

  test('the web stand-in exists', () {
    expect(File(webPath).existsSync(), isTrue,
        reason: 'the conditional export names it; without the file, web builds '
            'fall back to the ffi implementation and fail to compile');
  });

  test('the web stand-in imports no dart:ffi', () {
    // The entire reason it exists. Checked as an import directive rather than
    // as any mention of the string, since the file explains itself in prose
    // and naming the library it avoids is exactly how it should read.
    final imports = RegExp(r'''^import\s+'([^']+)''', multiLine: true)
        .allMatches(File(webPath).readAsStringSync())
        .map((RegExpMatch m) => m.group(1)!)
        .toList();
    expect(imports, isNot(contains('dart:ffi')));
  });

  test('every public name on native also exists on web', () {
    final native = publicApiOf(nativePath);
    final web = publicApiOf(webPath);

    final missing = native.difference(web).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: 'these are exported on native and absent on web, so an app '
          'referring to them compiles on one target and not the other: '
          '$missing',
    );
  });
}
