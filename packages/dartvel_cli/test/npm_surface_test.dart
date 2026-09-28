// What an npm package offers a module, read from its package.json and its
// TypeScript declarations.
//
// Every call answers later: in a browser the package is loaded on the first
// call, and on the backend it runs in Node, so a function TypeScript declares
// as returning `string` is a `Future<String>` in Dart. A declaration Dart
// cannot express -- an object type, a callback, a union -- is left out with
// the reason rather than turned into `Object?`, which would compile and tell
// the caller nothing.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/npm_surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory npmPackage(Map<String, Object?> manifest, Map<String, String> files) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_npm_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(p.join(dir.path, 'package.json')).writeAsStringSync(jsonEncode(manifest));
  for (final MapEntry<String, String> f in files.entries) {
    File(p.join(dir.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  return dir;
}

void main() {
  test('exported functions in the declarations become async operations', () {
    final DVNpmSurface surface = dvScanNpmPackage(npmPackage(
      <String, Object?>{
        'name': '@acme/text-kit',
        'version': '3.1.0',
        'module': 'dist/index.mjs',
        'types': 'dist/index.d.ts',
      },
      <String, String>{
        'dist/index.mjs': 'export function slug(t, sep) { return t; }\n',
        'dist/index.d.ts': '''
/** Turns text into a slug. */
export declare function slug(text: string, separator?: string): string;
export declare function words(text: string): Promise<string[]>;
export function count(items: Array<number>, strict: boolean): number;
export declare function scores(): Record<string, number>;
export declare function parse(text: string): { ok: boolean };
export declare function each(items: string[], visit: (s: string) => void): void;
export declare function pick(value: string | number): string;
declare function internal(): void;
export declare const version: string;
''',
      },
    ).path);

    expect(surface.name, '@acme/text-kit');
    expect(surface.version, '3.1.0');
    expect(surface.entry, 'dist/index.mjs');
    final Map<String, DVModuleOperation> ops = <String, DVModuleOperation>{
      for (final DVModuleOperation o in surface.operations) o.name: o,
    };
    expect(ops.keys, containsAll(<String>['slug', 'words', 'count', 'scores']));
    expect(ops['slug']!.returnType, 'Future<String>');
    expect(ops['slug']!.parameterList, 'String text, [String? separator]');
    expect(ops['slug']!.doc, 'Turns text into a slug.');
    expect(ops['words']!.returnType, 'Future<List<String>>');
    expect(ops['count']!.parameterList, 'List<num> items, bool strict');
    expect(ops['count']!.returnType, 'Future<num>');
    expect(ops['scores']!.returnType, 'Future<Map<String, num>>');
    expect(surface.skipped['parse'], contains('object type'));
    expect(surface.skipped['each'], contains('function'));
    expect(surface.skipped['pick'], contains('union'));
    expect(ops.containsKey('internal'), isFalse);
    expect(ops.containsKey('version'), isFalse);
  });

  test('a package that reaches for Node built-ins is not for a browser', () {
    DVNpmSurface scan(String code) => dvScanNpmPackage(npmPackage(
          <String, Object?>{'name': 'k', 'version': '1.0.0', 'main': 'index.js'},
          <String, String>{
            'index.js': code,
            'index.d.ts': 'export declare function f(): string;\n',
          },
        ).path);

    expect(scan('export function f() { return "x"; }').web, isTrue);
    expect(scan("import fs from 'node:fs';\nexport function f() {}").web,
        isFalse);
    expect(scan("const fs = require('fs');\nexports.f = () => 1;").web, isFalse);
  });

  test('a package with no declarations has no surface Dart can type', () {
    expect(
      () => dvScanNpmPackage(npmPackage(
        <String, Object?>{'name': 'k', 'version': '1.0.0', 'main': 'index.js'},
        <String, String>{'index.js': 'exports.f = () => 1;'},
      ).path),
      throwsA(isA<DVDartSurfaceRefused>().having(
          (DVDartSurfaceRefused e) => e.message, 'message', contains('DV-MODULE-010'))),
    );
  });
}
