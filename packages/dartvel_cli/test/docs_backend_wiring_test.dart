// The documentation site, from the build to the backend that serves it.
//
// The pieces were each written and each tested on their own -- a mount read
// from pubspec, a server that answers under it, a payload section carrying
// the compiled site -- and nothing joined them: the binary's entry point
// handed dartvelMain two arguments it does not take, which is a web-server
// build that fails to compile for every application, docs or not. These are
// the joins.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/docs_mount.dart';
import 'package:dartvel_cli/src/build/server_binary.dart';
import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_core/binary_payload.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Bytes that end with a snapshot trailer, which is all splicing checks.
Uint8List _standInExecutable() {
  final ByteData bytes = ByteData(64);
  bytes.setUint64(64 - 16, 16, Endian.little);
  bytes.setUint64(64 - 8, 0xf6f6dcdc, Endian.little);
  return bytes.buffer.asUint8List();
}

/// The named arguments of the first call to [function] in [source], at the
/// call's own level: an argument of an argument is not one of its own.
Set<String> _namedArguments(String source, String function) {
  final int start = source.indexOf('$function(');
  expect(start, isNot(-1), reason: 'no call to $function');
  final StringBuffer own = StringBuffer();
  int depth = 0;
  for (int i = start + function.length; i < source.length; i++) {
    final String c = source[i];
    if (c == '(') {
      depth++;
      if (depth == 1) continue;
    }
    if (c == ')' && --depth == 0) break;
    if (depth == 1) own.write(c);
  }
  return <String>{
    for (final RegExpMatch m
        in RegExp(r'^\s*(\w+):', multiLine: true).allMatches(own.toString()))
      m.group(1)!,
  };
}

/// The named parameters [declaration] declares, in the one-line signature the
/// backend generator writes.
Set<String> _namedParameters(String source, String declaration) {
  final RegExpMatch? signature =
      RegExp('${RegExp.escape(declaration)}\\(.*?\\{(.*?)\\}\\) async \\{')
          .firstMatch(source);
  expect(signature, isNotNull, reason: 'no $declaration in the backend');
  return <String>{
    for (final RegExpMatch m
        in RegExp(r'(\w+)(?:\s*=[^,]+)?(?:,|$)').allMatches(signature!.group(1)!))
      m.group(1)!,
  };
}

void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_docs_backend_');
    addTearDown(() => project.deleteSync(recursive: true));
    Directory(p.join(project.path, '.dart_tool')).createSync();
    Directory(p.join(project.path, 'lib', 'backend', 'functions'))
        .createSync(recursive: true);
  });

  Future<String> backend() async {
    await BackendGenerator.generate(
      root: project.path,
      backendDir: 'lib/backend',
      pkgName: 'shop',
      buildId: 'b',
      backendHost: '127.0.0.1',
      backendPort: 3000,
      apiBasePath: '/api',
    );
    return File(
            p.join(project.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
        .readAsStringSync();
  }

  test('every argument the binary hands dartvelMain is one it takes', () async {
    final Set<String> passed =
        _namedArguments(dvServerBinaryEntrypoint, 'gen.dartvelMain');
    final Set<String> taken =
        _namedParameters(await backend(), 'Future<void> dartvelMain');
    expect(passed, containsAll(<String>['docs', 'docsRoot']));
    expect(taken, containsAll(passed));
  });

  test('the backend serves the docs mount before the application, with '
      'Studio\'s sign-in', () async {
    final String routes = await backend();
    expect(
      _namedParameters(routes, 'Future<dv.ServerHandle> startBackend'),
      containsAll(<String>['docs', 'docsRoot']),
    );
    expect(
      routes,
      contains('core.DVDocsServer(mount: docs, root: docsRoot, '
          'adminMount: admin ?? '),
    );
    expect(routes, contains('await docsServer?.respond(request) ?? '));
    // dartvelMain passes both on to the server it starts.
    expect(routes, contains('docs: docs, docsRoot: docsRoot'));
  });

  group('the payload', () {
    late File library;
    late String webRoot;

    setUp(() {
      File(p.join(project.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
          .writeAsStringSync('// generated');
      library = File(p.join(project.path, 'libdartvel_shelf.so'))
        ..writeAsBytesSync(<int>[7, 7, 7]);
      webRoot = p.join(project.path, 'build', 'web');
      File(p.join(webRoot, 'index.html'))
        ..createSync(recursive: true)
        ..writeAsStringSync('<html><title>The site</title></html>');
      for (final String name in <String>[
        'index.html',
        'main.dart.js',
        'docs.json',
        'graph.json',
      ]) {
        File(p.join(webRoot, dvDocsPagesDirectory, name))
          ..createSync(recursive: true)
          ..writeAsStringSync('docs $name');
      }
    });

    Future<DVBinaryPayload> build({DVDocsMount? docs}) async {
      final DVServerBinaryResult result = await dvBuildServerBinary(
        root: project.path,
        library: library,
        webRoot: webRoot,
        docs: docs,
        docsRoot: p.join(webRoot, dvDocsPagesDirectory),
        run: (String executable, List<String> arguments,
            {String? workingDirectory}) async {
          File(arguments[arguments.indexOf('-o') + 1])
              .writeAsBytesSync(_standInExecutable());
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(result.ok, isTrue, reason: result.lines.join('\n'));
      return DVBinaryPayload.read(result.binary!.path)!;
    }

    test('carries the site in its own section, with its mount and access',
        () async {
      final DVBinaryPayload payload = await build(
        docs: const DVDocsMount(
            path: '/manual', enabled: true, access: DVDocsAccess.studio),
      );
      expect(payload.names, containsAll(<String>['docs', 'docs.mount']));
      expect(dvUnpackFiles(payload.section('docs')).keys,
          containsAll(<String>['index.html', 'docs.json', 'graph.json']));
      expect(jsonDecode(utf8.decode(payload.section('docs.mount'))),
          containsPair('access', 'studio'));
      // Never among the files the binary serves to anybody.
      expect(
        dvUnpackFiles(payload.section('web'))
            .keys
            .where((String path) => path.contains(dvDocsPagesDirectory)),
        isEmpty,
      );
    });

    test('carries none where the build has none', () async {
      for (final DVDocsMount? docs in <DVDocsMount?>[
        null,
        const DVDocsMount(path: '/docs', enabled: false),
      ]) {
        final DVBinaryPayload payload = await build(docs: docs);
        expect(payload.names, isNot(contains('docs')));
        expect(payload.names, isNot(contains('docs.mount')));
      }
    });
  });

  group('where a build puts the site', () {
    const DVDocsMount studio =
        DVDocsMount(path: '/manual', enabled: true, access: DVDocsAccess.studio);
    const DVDocsMount public =
        DVDocsMount(path: '/manual', enabled: true, access: DVDocsAccess.public);

    test('a server carries it outside the files it serves to anybody', () {
      expect(dvDocsPlacement(studio, server: true, studioServed: true),
          (directory: dvDocsPagesDirectory, problem: null));
      expect(dvDocsPlacement(public, server: true, studioServed: false),
          (directory: dvDocsPagesDirectory, problem: null));
    });

    test('behind Studio on a server that has no Studio is refused', () {
      final ({String? directory, String? problem}) placed =
          dvDocsPlacement(studio, server: true, studioServed: false);
      expect(placed.directory, isNull);
      expect(placed.problem, contains('dartvel.admin'));
    });

    test('a static site carries a public one at its mount', () {
      expect(dvDocsPlacement(public, server: false, studioServed: false),
          (directory: 'manual', problem: null));
    });

    test('a static site refuses one behind Studio, which it cannot keep',
        () {
      final ({String? directory, String? problem}) placed =
          dvDocsPlacement(studio, server: false, studioServed: false);
      expect(placed.directory, isNull);
      expect(placed.problem, contains('access: public'));
      expect(placed.problem, contains('web-server'));
    });
  });
}
