// What a web-server binary carries of Studio.
//
// The binary serves every file under web/ in its pack to anybody who asks,
// so nothing of Studio's may ride in there. Studio's data -- the project graph
// and each page's structure -- goes under admin/ in the pack, every file
// protected, with the mount in a section of its own; Studio's code, the parts
// of the application's deferred Studio library, goes in a section the binary
// keeps in memory and serves only to a session with the Studio grant.
//
// No compiler here: the compile step is handed a stand-in executable that
// ends the way `dart compile exe` output does, and the payload is read back
// out of build/server with the same reader the binary uses at start.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/admin_mount.dart';
import 'package:dartvel_cli/src/build/docs_mount.dart';
import 'package:dartvel_cli/src/build/server_binary.dart';
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

void main() {
  late Directory project;
  late File library;
  late String webRoot;
  late String studioRoot;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_server_admin_payload_');
    addTearDown(() => project.deleteSync(recursive: true));
    File(p.join(project.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('// generated');
    library = File(p.join(project.path, 'libdartvel_shelf.so'))
      ..writeAsBytesSync(<int>[7, 7, 7]);
    webRoot = p.join(project.path, 'build', 'web');
    File(p.join(webRoot, 'index.html'))
      ..createSync(recursive: true)
      ..writeAsStringSync('<html><title>The site</title></html>');
    File(p.join(webRoot, 'main.dart.js'))
      ..createSync(recursive: true)
      ..writeAsStringSync('/* public */');
    studioRoot = p.join(project.path, 'build', 'studio');
    File(p.join(studioRoot, 'data', 'graph.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('studio graph.json');
    File(p.join(studioRoot, 'parts', 'main.dart.js_7.part.js'))
      ..createSync(recursive: true)
      ..writeAsStringSync('/* Studio screens */');
  });

  Future<DVBinaryPayload> build({DVAdminMount? admin}) async {
    final DVServerBinaryResult result = await dvBuildServerBinary(
      root: project.path,
      library: library,
      webRoot: webRoot,
      admin: admin,
      adminRoot: p.join(studioRoot, 'data'),
      studioPartsRoot: p.join(studioRoot, 'parts'),
      run: (String executable, List<String> arguments,
          {String? workingDirectory}) async {
        File(arguments[arguments.indexOf('-o') + 1])
            .writeAsBytesSync(_standInExecutable());
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(result.ok, isTrue, reason: result.lines.join('\n'));
    final DVBinaryPayload? payload = DVBinaryPayload.read(result.binary!.path);
    expect(payload, isNotNull);
    return payload!;
  }

  DVAssetPack packOf(DVBinaryPayload payload) {
    final ({int offset, int length}) at = payload.locate('assets')!;
    return DVAssetPack.open(payload.path, offset: at.offset, length: at.length)!;
  }

  test("carries Studio's data under admin/ in the pack, protected, with its mount", () async {
    final DVBinaryPayload payload = await build(
      admin: const DVAdminMount(
          path: '/ops/panel', enabled: true, requiresAuth: true),
    );

    expect(payload.names, containsAll(<String>['native', 'assets', 'admin.mount']));
    // Nothing is carried the old way, as a stream written out at start.
    expect(payload.names, isNot(contains('web')));
    expect(payload.names, isNot(contains('admin')));
    final DVAssetPack pack = packOf(payload);
    final List<String> admin = <String>[
      for (final String path in pack.paths)
        if (path.startsWith('admin/')) path.substring(6),
    ];
    expect(admin, <String>['graph.json']);
    expect(utf8.decode(pack.read(pack['admin/graph.json']!)), 'studio graph.json');
    expect(pack.assets.where((DVPackedAsset a) => a.path.startsWith('admin/')).every((DVPackedAsset a) => a.protected),
        isTrue);

    // The mount the build decided, not the default: a project that moved its
    // admin somewhere private must not find it back at /__studio.
    expect(jsonDecode(utf8.decode(payload.section('admin.mount'))),
        <String, Object?>{'path': '/ops/panel', 'requiresAuth': true});
  });

  test("carries Studio's code in a section of its own, never among the web "
      'files', () async {
    final DVBinaryPayload payload = await build(
      admin: const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: true),
    );

    expect(dvUnpackFiles(payload.section('studio')).keys,
        <String>['main.dart.js_7.part.js']);
    final List<String> web = <String>[
      for (final String path in packOf(payload).paths)
        if (path.startsWith('web/')) path.substring(4),
    ];
    expect(web, containsAll(<String>['index.html', 'main.dart.js']));
    expect(web.where((String path) => path.contains('part')), isEmpty);
  });

  test('keeps Studio\'s code in memory: the binary never writes it to disk',
      () {
    expect(dvServerBinaryEntrypoint,
        contains("dvUnpackFiles(payload.section('studio'))"));
    expect(dvServerBinaryEntrypoint,
        isNot(contains("dvExtractFiles(")));
    expect(dvServerBinaryEntrypoint, contains('studioParts:'));
  });

  test('never puts Studio among the web files', () async {
    final DVBinaryPayload payload = await build(
      admin: const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: false),
    );

    final DVAssetPack pack = packOf(payload);
    expect(pack.paths, contains('web/index.html'));
    expect(pack.paths.where((String path) => path.contains('__admin')), isEmpty);
    expect(pack['web/index.html']!.protected, isFalse);
  });

  test('carries no admin where the build has none', () async {
    for (final DVAdminMount? admin in <DVAdminMount?>[
      null,
      const DVAdminMount(path: '/__studio', enabled: false, requiresAuth: true),
    ]) {
      final DVBinaryPayload payload = await build(admin: admin);
      expect(payload.names, isNot(contains('admin.mount')));
      expect(packOf(payload).paths.where((String path) => path.startsWith('admin/')), isEmpty);
      expect(payload.names, isNot(contains('studio')));
    }
  });

  test('carries the docs site under docs/ in the pack, protected, with its mount', () async {
    final String docsRoot = p.join(webRoot, dvDocsPagesDirectory);
    File(p.join(docsRoot, 'index.html'))
      ..createSync(recursive: true)
      ..writeAsStringSync('<html><title>Docs</title></html>');
    final DVServerBinaryResult result = await dvBuildServerBinary(
      root: project.path,
      library: library,
      webRoot: webRoot,
      docs: const DVDocsMount(path: '/docs', enabled: true, access: DVDocsAccess.studio),
      docsRoot: docsRoot,
      run: (String executable, List<String> arguments, {String? workingDirectory}) async {
        File(arguments[arguments.indexOf('-o') + 1]).writeAsBytesSync(_standInExecutable());
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(result.ok, isTrue, reason: result.lines.join('\n'));
    final DVBinaryPayload payload = DVBinaryPayload.read(result.binary!.path)!;
    expect(payload.names, contains('docs.mount'));
    expect(payload.names, isNot(contains('docs')));
    final DVAssetPack pack = packOf(payload);
    expect(pack['docs/index.html']?.protected, isTrue);
    // The docs pages are never among the public web files.
    expect(pack.paths.where((String path) => path.startsWith('web/__docs')), isEmpty);
  });
}
