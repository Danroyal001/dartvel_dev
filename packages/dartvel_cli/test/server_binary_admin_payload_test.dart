// What a web-server binary carries of the admin dashboard.
//
// The binary serves every file of its 'web' section to anybody who asks, so
// the dashboard cannot ride in there: it was left out, and so the one file
// that is the deployment had no admin at all. It goes in a section of its
// own, with the mount it is served at, and the web section still carries
// none of it.
//
// No compiler here: the compile step is handed a stand-in executable that
// ends the way `dart compile exe` output does, and the payload is read back
// out of build/server with the same reader the binary uses at start.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/admin_mount.dart';
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
    for (final String name in <String>[
      'index.html',
      'admin.css',
      'admin.js',
      'graph.json',
    ]) {
      File(p.join(webRoot, '__admin', name))
        ..createSync(recursive: true)
        ..writeAsStringSync('studio $name');
    }
  });

  Future<DVBinaryPayload> build({DVAdminMount? admin}) async {
    final DVServerBinaryResult result = await dvBuildServerBinary(
      root: project.path,
      library: library,
      webRoot: webRoot,
      admin: admin,
      adminRoot: p.join(webRoot, '__admin'),
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

  test('carries the dashboard in its own section, with its mount', () async {
    final DVBinaryPayload payload = await build(
      admin: const DVAdminMount(
          path: '/ops/panel', enabled: true, requiresAuth: true),
    );

    expect(payload.names, containsAll(<String>['web', 'admin', 'admin.mount']));
    final Map<String, List<int>> admin =
        dvUnpackFiles(payload.section('admin'));
    expect(admin.keys,
        unorderedEquals(<String>['index.html', 'admin.css', 'admin.js', 'graph.json']));
    expect(utf8.decode(admin['index.html']!), 'studio index.html');

    // The mount the build decided, not the default: a project that moved its
    // admin somewhere private must not find it back at /__studio.
    expect(jsonDecode(utf8.decode(payload.section('admin.mount'))),
        <String, Object?>{'path': '/ops/panel', 'requiresAuth': true});
  });

  test('never puts the dashboard in the web section', () async {
    final DVBinaryPayload payload = await build(
      admin: const DVAdminMount(
          path: '/__studio', enabled: true, requiresAuth: false),
    );

    final Map<String, List<int>> web = dvUnpackFiles(payload.section('web'));
    expect(web.keys, contains('index.html'));
    expect(web.keys.where((String path) => path.contains('__admin')), isEmpty);
  });

  test('carries no admin where the build has none', () async {
    for (final DVAdminMount? admin in <DVAdminMount?>[
      null,
      const DVAdminMount(path: '/__studio', enabled: false, requiresAuth: true),
    ]) {
      final DVBinaryPayload payload = await build(admin: admin);
      expect(payload.names, isNot(contains('admin')));
      expect(payload.names, isNot(contains('admin.mount')));
    }
  });
}
