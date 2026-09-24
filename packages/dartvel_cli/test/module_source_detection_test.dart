// What a local path is, read from what is in it.
//
// Detection is a proposal, not a verdict: `dartvel add --dry-run` prints what
// was detected and what would be generated, and --target and --as override
// it. So the job here is to be right about the obvious cases and honest
// about the rest -- a source that matches nothing is DV-MODULE-009, which
// names what was found rather than reporting failure, because "could not
// detect" tells somebody nothing about what to do next.
import 'dart:io';

import 'package:dartvel_cli/src/modules/source_detection.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _dir(Map<String, String> files) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_detect_');
  addTearDown(() => root.deleteSync(recursive: true));
  files.forEach((String name, String body) {
    final File file = File(p.join(root.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(body);
  });
  return root.path;
}

DVSourceKind _kindOf(Map<String, String> files) =>
    dvDetectSource(_dir(files)).kind;

void main() {
  test('a Dartvel project is used directly, and nothing is generated', () {
    final DVDetectedSource found = dvDetectSource(_dir(<String, String>{
      'pubspec.yaml': 'name: store\ndartvel:\n  module:\n    id: store\n',
    }));

    expect(found.kind, DVSourceKind.dartvel);
    expect(found.generates, isFalse);
    expect(found.mechanism, 'used directly');
  });

  test('a Dart package with no dartvel section is not a module', () {
    // The mechanical test the specification gives: it contributes nothing to
    // the project graph, so it is an ordinary dependency.
    final DVDetectedSource found = dvDetectSource(_dir(<String, String>{
      'pubspec.yaml': 'name: intl\n',
    }));

    expect(found.kind, DVSourceKind.dartPackage);
    expect(found.generates, isFalse);
  });

  test('each foreign shape is read as the boundary it crosses', () {
    expect(_kindOf(<String, String>{'Package.swift': ''}), DVSourceKind.apple);
    expect(_kindOf(<String, String>{'Vendor.xcframework/x': ''}),
        DVSourceKind.apple);
    expect(_kindOf(<String, String>{'build.gradle': ''}), DVSourceKind.jvm);
    expect(_kindOf(<String, String>{'pom.xml': ''}), DVSourceKind.jvm);
    expect(_kindOf(<String, String>{'scanner.aar': ''}), DVSourceKind.jvm);
    expect(_kindOf(<String, String>{'Cargo.toml': ''}), DVSourceKind.rust);
    expect(_kindOf(<String, String>{'CMakeLists.txt': ''}), DVSourceKind.c);
    expect(_kindOf(<String, String>{'engine.h': ''}), DVSourceKind.c);
    expect(_kindOf(<String, String>{'engine.wasm': ''}), DVSourceKind.wasm);
    expect(_kindOf(<String, String>{'package.json': '{}'}), DVSourceKind.npm);
    expect(_kindOf(<String, String>{'openapi.json': '{}'}),
        DVSourceKind.describedApi);
    expect(_kindOf(<String, String>{'schema.graphql': ''}),
        DVSourceKind.describedApi);
    expect(_kindOf(<String, String>{'service.proto': ''}),
        DVSourceKind.describedApi);
  });

  test('a described API needs no binding at all', () {
    // The distinction the specification draws: OpenAPI, GraphQL and gRPC are
    // sources, not bindings. There is no foreign runtime and no artifact --
    // typed calls over DV.Http and nothing else.
    final DVDetectedSource found = dvDetectSource(_dir(<String, String>{
      'openapi.yaml': 'openapi: 3.0.0\n',
    }));

    expect(found.generates, isTrue);
    expect(found.binding, isNull);
    expect(found.mechanism, contains('DV.Http'));
  });

  test('Swift, C and Rust all cross the same boundary', () {
    // Kind, source language and target are three dimensions. There is no
    // DVSwiftBinding: Swift, Objective-C, C++ and Rust all reach Dart across
    // the C ABI, so all of them are the FFI kind.
    for (final Map<String, String> files in <Map<String, String>>[
      <String, String>{'Package.swift': ''},
      <String, String>{'CMakeLists.txt': ''},
      <String, String>{'Cargo.toml': ''},
    ]) {
      expect(dvDetectSource(_dir(files)).binding, 'DVFfiBinding');
    }
    expect(dvDetectSource(_dir(<String, String>{'pom.xml': ''})).binding,
        'DVJniBinding');
  });

  test('a Dartvel project wins over anything else beside it', () {
    // A Dartvel module may perfectly well contain a Cargo.toml for its own
    // native code. Reading that as a Rust source would wrap a module that is
    // already a module.
    expect(
      _kindOf(<String, String>{
        'pubspec.yaml': 'name: scanner\ndartvel:\n  module:\n    id: scanner\n',
        'native/linux/Cargo.toml': '',
        'Cargo.toml': '',
      }),
      DVSourceKind.dartvel,
    );
  });

  test('a directory matching nothing names what it found', () {
    final DVDetectedSource found = dvDetectSource(_dir(<String, String>{
      'README.md': '',
      'notes.txt': '',
    }));

    expect(found.kind, DVSourceKind.unknown);
    expect(found.code, 'DV-MODULE-009');
    // Naming what is there is the whole point: "could not detect" tells
    // somebody nothing about what to do next.
    expect(found.reason, contains('README.md'));
  });

  test('an empty directory says it is empty rather than listing nothing', () {
    final DVDetectedSource found = dvDetectSource(_dir(<String, String>{}));

    expect(found.kind, DVSourceKind.unknown);
    expect(found.reason, contains('empty'));
  });

  test('a path that does not exist is not a detection failure', () {
    // Distinct from DV-MODULE-009: nothing was inspected, so nothing can be
    // named, and telling somebody their SDK is unrecognised when they mistyped
    // a path sends them looking in the wrong place.
    final DVDetectedSource found =
        dvDetectSource(p.join(_dir(<String, String>{}), 'nowhere'));

    expect(found.kind, DVSourceKind.missing);
    expect(found.code, isNull);
  });
}
