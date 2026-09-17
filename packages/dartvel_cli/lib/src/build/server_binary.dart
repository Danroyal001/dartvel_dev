/// The web-server build's output: one executable file that is the whole
/// deployment.
///
/// The monolith in the specification is a single native backend binary, and
/// what surrounds it expects one at build/server: the image `dartvel deploy`
/// writes runs /app/server, and the units `dartvel infra` renders start
/// /opt/<app>/server.
///
/// `dart compile exe` alone does not make that file. The HTTP server is a
/// Rust library the backend loads through FFI, the pages are assembled from a
/// web shell and the app's code assets, and a compiled program has none of
/// them. So the build compiles the backend and carries the library and the
/// web files inside the executable as a `DVBinaryPayload`. On start the
/// binary loads the library from memory, writes the web files once into its
/// data directory, and serves.
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/binary_payload.dart';
import 'package:path/path.dart' as p;

import 'admin_mount.dart';

/// Where the output goes, relative to the project.
String dvServerBinaryPath({bool windows = false}) =>
    p.join('build', windows ? 'server.exe' : 'server');

/// The platform directory and file name dartvel_shelf ships its native
/// library under, for this host.
///
/// A host the server is not built for gets a directory named after its ABI,
/// which does not exist, so the lookup reports that host by name instead of
/// embedding another host's library.
({String subdir, String name}) dvHostServerLibrary() =>
    dvServerLibraryFor(Abi.current()) ??
    (subdir: '${Abi.current()}', name: 'libdartvel_shelf.so');

/// The directory and file name of dartvel_shelf's library for [abi], or null
/// for an ABI it is not built for.
///
/// Read from the ABI and not from Platform.version, which says `linux_arm64`
/// and `windows_arm64`: checking it for `aarch64` and `ARM64` sent both arm64
/// hosts to the x64 library.
({String subdir, String name})? dvServerLibraryFor(Abi abi) => switch (abi) {
      Abi.linuxX64 => (subdir: 'linux-x64', name: 'libdartvel_shelf.so'),
      Abi.linuxArm64 => (subdir: 'linux-arm64', name: 'libdartvel_shelf.so'),
      Abi.macosArm64 => (subdir: 'macos-arm64', name: 'libdartvel_shelf.dylib'),
      Abi.macosX64 => (subdir: 'macos-x64', name: 'libdartvel_shelf.dylib'),
      Abi.windowsX64 => (subdir: 'windows-x64', name: 'dartvel_shelf.dll'),
      Abi.windowsArm64 => (subdir: 'windows-arm64', name: 'dartvel_shelf.dll'),
      _ => null,
    };

/// The native library a server build embeds, or why there is none.
class DVServerLibraryLookup {
  const DVServerLibraryLookup.found(File this.file) : problem = null;
  const DVServerLibraryLookup.missing(String this.problem) : file = null;

  final File? file;
  final String? problem;
}

/// Finds dartvel_shelf's library for [subdir] through the project's
/// resolved packages, which is the copy the project actually builds against.
DVServerLibraryLookup dvLocateServerLibrary(
  String root, {
  required String subdir,
  required String name,
}) {
  final File config = File(p.join(root, '.dart_tool', 'package_config.json'));
  Map<String, Object?>? shelf;
  if (config.existsSync()) {
    try {
      final Object? decoded = jsonDecode(config.readAsStringSync());
      final Object? packages = decoded is Map ? decoded['packages'] : null;
      if (packages is List) {
        for (final Object? entry in packages) {
          if (entry is Map && entry['name'] == 'dartvel_shelf') {
            shelf = entry.cast<String, Object?>();
          }
        }
      }
    } on FormatException {
      shelf = null;
    }
  }
  if (shelf == null) {
    return const DVServerLibraryLookup.missing(
      'this project does not resolve dartvel_shelf, which is the server a '
      'backend binary runs. Add it to dependencies and run pub get.',
    );
  }
  final Uri base = config.parent.uri;
  final Uri packageRoot = base.resolve('${shelf['rootUri']}'.endsWith('/')
      ? '${shelf['rootUri']}'
      : '${shelf['rootUri']}/');
  final File library = File(
      p.join(File.fromUri(packageRoot).path, 'lib', 'native', subdir, name));
  if (!library.existsSync()) {
    return DVServerLibraryLookup.missing(
      'dartvel_shelf has no native server library for $subdir (looked for '
      '${library.path}). A server binary embeds that library, so it can only '
      'be built on a host the library has been built for.',
    );
  }
  return DVServerLibraryLookup.found(library);
}

/// The web files a binary carries: the shell and the app's code and assets.
///
/// Not the admin dashboard, which the web-server build writes under
/// `__admin/`: the binary serves every file it carries to anybody who asks,
/// and the dashboard is only served behind its own gate. Not the debug
/// symbols, which no browser loads.
Map<String, List<int>> dvServerWebFiles(String webRoot) {
  final Map<String, List<int>> files = <String, List<int>>{};
  final Directory root = Directory(webRoot);
  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String relative =
        p.relative(entity.path, from: root.path).replaceAll(r'\', '/');
    if (relative.startsWith('__admin/') ||
        relative.endsWith('.symbols') ||
        relative == '.last_build_id') {
      continue;
    }
    files[relative] = entity.readAsBytesSync();
  }
  return files;
}

/// The admin dashboard a binary carries, as sections of its own: `admin`, the
/// dashboard's files, and `admin.mount`, where it is served and whether a
/// sign-in is required.
///
/// Not in the `web` section, whose every file is served to anybody. Nothing
/// at all when the build has no admin, so a release build that never asked
/// for one carries no dashboard to find.
Map<String, List<int>> dvServerAdminSections({
  required DVAdminMount? admin,
  required String? adminRoot,
}) {
  if (admin == null || !admin.enabled || adminRoot == null) {
    return const <String, List<int>>{};
  }
  final Directory root = Directory(adminRoot);
  if (!root.existsSync()) return const <String, List<int>>{};
  final Map<String, List<int>> files = <String, List<int>>{
    for (final FileSystemEntity entity in root.listSync(recursive: true))
      if (entity is File)
        p.relative(entity.path, from: root.path).replaceAll(r'\', '/'):
            entity.readAsBytesSync(),
  };
  if (files.isEmpty) return const <String, List<int>>{};
  return <String, List<int>>{
    'admin': dvPackFiles(files),
    'admin.mount': utf8.encode(jsonEncode(<String, Object?>{
      'path': admin.path,
      'requiresAuth': admin.requiresAuth,
    })),
  };
}

/// The binary's entry point: take the library, the web files and the admin
/// dashboard out of the executable, choose the database, run the backend.
const String dvServerBinaryEntrypoint = r'''
// GENERATED by dartvel build web-server -- do not edit.
//
// The web-server binary's entry point. It carries the native server library
// and the web app inside itself, keeps its data in dartvel_data beside
// itself (DARTVEL_DATA_DIR moves it), and uses SQLite there unless
// DATABASE_URL names another database. Patches a self-hosted Shorebird patch
// source is given go in dartvel_data/updates. The admin dashboard, when the
// build has one, is written to dartvel_data/.admin -- beside the web files,
// never among them, because every web file is served to anybody -- and
// served at its mount by the backend.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_core/dartvel.dart' as core;
import 'package:dartvel_shelf/dartvel_shelf.dart' show embedNativeServerLibrary;

import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  final DVBinaryPayload? payload =
      DVBinaryPayload.read(Platform.resolvedExecutable);
  if (payload == null) {
    stderr.writeln('dartvel: this program carries no web-server build. Run '
        'build/server, which dartvel build web-server writes.');
    exit(70);
  }
  embedNativeServerLibrary(payload.section('native'));

  final String separator = Platform.pathSeparator;
  final String data = Platform.environment['DARTVEL_DATA_DIR'] ??
      '${File(Platform.resolvedExecutable).parent.path}${separator}dartvel_data';
  Directory(data).createSync(recursive: true);
  final String? webRoot = payload.names.contains('web')
      ? dvExtractFiles(payload.section('web'), '$data$separator.web')
      : null;
  // The dashboard and its mount. A mount that does not read back as one
  // requires a sign-in: failing closed is a dashboard nobody can open, and
  // failing open is one anybody can.
  core.DVAdminMount? admin;
  String? adminRoot;
  if (payload.names.contains('admin') && payload.names.contains('admin.mount')) {
    final Object? mount = jsonDecode(utf8.decode(payload.section('admin.mount')));
    final Object? path = mount is Map ? mount['path'] : null;
    if (path is String && path.startsWith('/') && path.length > 1) {
      admin = core.DVAdminMount(
        path: path,
        enabled: true,
        requiresAuth: mount is Map && mount['requiresAuth'] == false ? false : true,
      );
      adminRoot = dvExtractFiles(payload.section('admin'), '$data$separator.admin');
    }
  }

  final String database = '$data${separator}data.db';
  final String? url = const core.DVSecrets().maybeGet('DATABASE_URL');
  if (url == null || url.trim().isEmpty) {
    stdout.writeln(File(database).existsSync()
        ? 'dartvel: SQLite database $database'
        : 'dartvel: no DATABASE_URL, creating SQLite database $database');
  }

  try {
    await gen.dartvelMain(
      arguments,
      webRoot: webRoot,
      admin: admin,
      adminRoot: adminRoot,
      // Where a self-hosted Shorebird patch source keeps what is published
      // to it, when shorebird.yaml says this server is one.
      updatesRoot: Platform.environment['DARTVEL_UPDATES_DIR'] ??
          '$data${separator}updates',
      defaultDatabase: core.DVDatabaseConnection(
        engine: core.DVDatabaseEngine.sqlite,
        database: database,
      ),
    );
  } on core.DVProcessConfigurationError catch (error) {
    // EX_CONFIG: a supervisor restarting this will not fix it.
    stderr.writeln('dartvel: $error');
    exit(78);
  }
}
''';

/// Runs a process; [Process.run] outside tests.
typedef DVServerBinaryRun = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// What a server build did.
class DVServerBinaryResult {
  const DVServerBinaryResult({
    required this.ok,
    required this.lines,
    this.binary,
  });

  final bool ok;
  final List<String> lines;
  final File? binary;
}

/// Writes the entry point, compiles it, and carries [library] and the files
/// of [webRoot] inside the result at build/server. Generation has already
/// run: `.dart_tool/dartvel_backend_routes.g.dart` is what this compiles.
Future<DVServerBinaryResult> dvBuildServerBinary({
  required String root,
  required File library,
  required DVServerBinaryRun run,
  String? webRoot,
  DVAdminMount? admin,
  String? adminRoot,
  String dart = 'dart',
}) async {
  final File routes =
      File(p.join(root, '.dart_tool', 'dartvel_backend_routes.g.dart'));
  if (!routes.existsSync()) {
    return const DVServerBinaryResult(ok: false, lines: <String>[
      'No generated backend at .dart_tool/dartvel_backend_routes.g.dart. Run '
          '`dartvel routes` first.',
    ]);
  }
  final File entry =
      File(p.join(root, '.dart_tool', 'dartvel_server_binary.dart'))
        ..writeAsStringSync(dvServerBinaryEntrypoint);
  final File compiled =
      File(p.join(root, '.dart_tool', 'dartvel_server_binary.exe'));

  final ProcessResult result = await run(
    dart,
    <String>['compile', 'exe', entry.path, '-o', compiled.path],
    workingDirectory: root,
  );
  if (result.exitCode != 0) {
    return DVServerBinaryResult(ok: false, lines: <String>[
      'dart compile exe exited ${result.exitCode}:',
      ...'${result.stdout}\n${result.stderr}'
          .split('\n')
          .where((String l) => l.trim().isNotEmpty),
    ]);
  }

  final Map<String, List<int>> sections = <String, List<int>>{
    'native': library.readAsBytesSync(),
    if (webRoot != null) 'web': dvPackFiles(dvServerWebFiles(webRoot)),
    ...dvServerAdminSections(admin: admin, adminRoot: adminRoot),
  };
  final Uint8List spliced;
  try {
    spliced = DVBinaryPayload.splice(compiled.readAsBytesSync(), sections);
  } on FormatException catch (error) {
    return DVServerBinaryResult(ok: false, lines: <String>[
      'The compiled backend cannot carry the web app: ${error.message}.',
    ]);
  }
  final String output =
      p.join(root, dvServerBinaryPath(windows: Platform.isWindows));
  Directory(p.dirname(output)).createSync(recursive: true);
  final File binary = File(output)..writeAsBytesSync(spliced, flush: true);
  compiled.deleteSync();
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['755', binary.path]);
  }

  final double megabytes = binary.lengthSync() / (1024 * 1024);
  final String shown = dvServerBinaryPath(windows: Platform.isWindows);
  return DVServerBinaryResult(
    ok: true,
    binary: binary,
    lines: <String>[
      '$shown (${megabytes.toStringAsFixed(1)} MB): the backend, '
          '${webRoot == null ? 'with no web app' : 'the web app'}'
          '${sections.containsKey('admin') ? ', the admin dashboard at ${admin!.path}' : ''} '
          'and the native server, in one file.',
      'Run it anywhere: ./$shown. It keeps its data in dartvel_data beside '
          'itself, in SQLite unless DATABASE_URL is set.',
    ],
  );
}
