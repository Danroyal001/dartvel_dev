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
/// web files inside the executable as a `DVBinaryPayload`: the library as it
/// is, the web files as an indexed pack (see server_assets.dart). On start
/// the binary reads the pack's index and nothing else; a file is read from
/// the executable when a request asks for it, and nothing is ever written
/// out but the binary's own data and cache.
library;

import 'dart:convert';
import 'dart:ffi' show Abi, DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_core/binary_payload.dart';
import 'package:path/path.dart' as p;

import 'admin_mount.dart';
import 'server_assets.dart';
import 'server_compile.dart';

export 'server_assets.dart' show DVAssetCompression, dvAssetCompression;

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

/// Where the admin dashboard a binary carries is served, as a section of its
/// own: `admin.mount`, its mount and whether a sign-in is required. The
/// dashboard's files are in the pack under `admin/`, every one protected.
///
/// Nothing at all when the build has no admin, so a release build that never
/// asked for one carries no dashboard to find.
Map<String, List<int>> dvServerAdminSections({
  required DVAdminMount? admin,
  required String? adminRoot,
}) {
  if (admin == null || !admin.enabled || adminRoot == null) {
    return const <String, List<int>>{};
  }
  final Directory root = Directory(adminRoot);
  if (!root.existsSync() || !root.listSync(recursive: true).any((FileSystemEntity e) => e is File)) {
    return const <String, List<int>>{};
  }
  return <String, List<int>>{
    'admin.mount': utf8.encode(jsonEncode(<String, Object?>{
      'path': admin.path,
      'requiresAuth': admin.requiresAuth,
    })),
  };
}

/// The binary's entry point: find the native library and the pack inside the
/// executable, choose the database, run the backend.
const String dvServerBinaryEntrypoint = r'''
// GENERATED by dartvel build web-server -- do not edit.
//
// The web-server binary's entry point. It carries the native server library
// and the web app inside itself and reads each from where it lies: the
// library is opened from its range of this file, and a web file is read when
// a request asks for it. Nothing of the app is written out. The binary keeps
// its data in dartvel_data beside itself (DARTVEL_DATA_DIR moves it), and
// uses SQLite there unless DATABASE_URL names another database; what it
// decodes for a client is kept in dartvel_data/cache (DARTVEL_CACHE_DIR),
// one directory per build, safe to delete. Patches a self-hosted Shorebird
// patch source is given go in dartvel_data/updates. The admin dashboard, when
// the build has one, is in the pack apart from the web files -- every one of
// which is served to anybody -- and served at its mount by the backend.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/binary_payload.dart';
import 'package:dartvel_core/dartvel.dart' as core;
import 'package:dartvel_shelf/asset_cache.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' show embedNativeServerLibraryAt;
import 'package:dartvel_shelf/loading_units.dart';

import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  final DVBinaryPayload? payload =
      DVBinaryPayload.read(Platform.resolvedExecutable);
  final ({int offset, int length})? native = payload?.locate('native');
  if (payload == null || native == null) {
    stderr.writeln('dartvel: this program carries no web-server build. Run '
        'build/server, which dartvel build web-server writes.');
    exit(70);
  }
  embedNativeServerLibraryAt(payload.path,
      offset: native.offset, length: native.length);
  // Code the program reaches only through deferred imports: mapped from
  // this file the first time a request needs it, and never before.
  await dvInstallLoadingUnits(payload);

  final String separator = Platform.pathSeparator;
  final String data = Platform.environment['DARTVEL_DATA_DIR'] ??
      '${File(payload.path).parent.path}${separator}dartvel_data';
  Directory(data).createSync(recursive: true);
  // What a build of this server from before the pack wrote out at start.
  for (final String extracted in <String>['.web', '.admin']) {
    final Directory old = Directory('$data$separator$extracted');
    if (old.existsSync()) old.deleteSync(recursive: true);
  }

  // The web app and the dashboard, read in place. Their roots name no
  // directory: every read of them goes through the pack.
  String? webRoot;
  String? adminRoot;
  final ({int offset, int length})? assets = payload.locate('assets');
  if (assets != null) {
    final DVAssetPack? pack = DVAssetPack.open(payload.path,
        offset: assets.offset, length: assets.length);
    if (pack == null) {
      stderr.writeln('dartvel: the web app in this binary cannot be read.');
      exit(70);
    }
    if (pack.paths.any((String path) => path.startsWith('web/'))) {
      webRoot = '${payload.path}${separator}web';
      DVAssetSources.register(webRoot, DVPackedAssets(pack, prefix: 'web/'));
    }
    if (pack.paths.any((String path) => path.startsWith('admin/'))) {
      adminRoot = '${payload.path}${separator}admin';
      DVAssetSources.register(adminRoot, DVPackedAssets(pack, prefix: 'admin/'));
    }
    final String cache = Platform.environment['DARTVEL_CACHE_DIR'] ??
        '$data${separator}cache';
    DVAssetCache.current = DVAssetCache(
      directory: '$cache${separator}assets',
      imagesDirectory: '$cache${separator}images',
    )..forBuild(pack.buildId);
  }

  // The dashboard's mount. A mount that does not read back as one requires a
  // sign-in: failing closed is a dashboard nobody can open, and failing open
  // is one anybody can.
  core.DVAdminMount? admin;
  if (adminRoot != null && payload.names.contains('admin.mount')) {
    final Object? mount = jsonDecode(utf8.decode(payload.section('admin.mount')));
    final Object? path = mount is Map ? mount['path'] : null;
    if (path is String && path.startsWith('/') && path.length > 1) {
      admin = core.DVAdminMount(
        path: path,
        enabled: true,
        requiresAuth: mount is Map && mount['requiresAuth'] == false ? false : true,
      );
    }
  }
  if (admin == null) adminRoot = null;

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
  DVAssetCompression compression = DVAssetCompression.brotli,
  bool units = false,
  Map<String, String> defines = const <String, String>{},
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
  // In loading units where the host and the native library can load them:
  // what a request never needs is never mapped.
  final bool split = units && dvServerLibraryLoadsUnits(library.path);
  final DVCompiledServer compiled = await dvCompileServer(
    root: root,
    entry: entry.path,
    run: run,
    dart: dart,
    units: split,
    defines: defines,
  );
  if (!compiled.ok) {
    return DVServerBinaryResult(ok: false, lines: compiled.lines);
  }

  final Map<String, List<int>> adminSections =
      dvServerAdminSections(admin: admin, adminRoot: adminRoot);
  final DVServerAssetsResult assets = await dvServerAssetPack(
    projectRoot: root,
    webRoot: webRoot,
    admin: adminSections.isEmpty ? null : admin,
    adminRoot: adminRoot,
    compression: compression,
    codecLibrary: library.path,
  );
  final Map<String, List<int>> sections = <String, List<int>>{
    'native': library.readAsBytesSync(),
    'assets': assets.pack,
    ...adminSections,
    for (final MapEntry<int, Uint8List> unit in compiled.units.entries)
      'unit.${unit.key}': unit.value,
  };
  final Uint8List spliced;
  try {
    spliced = DVBinaryPayload.splice(
      compiled.executable!,
      sections,
      // Each unit on a 64 KiB boundary, so it is mapped straight from the
      // file.
      aligned: <String>{for (final int id in compiled.units.keys) 'unit.$id'},
    );
  } on FormatException catch (error) {
    return DVServerBinaryResult(ok: false, lines: <String>[
      'The compiled backend cannot carry the web app: ${error.message}.',
    ]);
  }
  final String output =
      p.join(root, dvServerBinaryPath(windows: Platform.isWindows));
  Directory(p.dirname(output)).createSync(recursive: true);
  final File binary = File(output)..writeAsBytesSync(spliced, flush: true);
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
          '${sections.containsKey('admin.mount') ? ', the admin dashboard at ${admin!.path}' : ''} '
          'and the native server, in one file.',
      'Run it anywhere: ./$shown. It keeps its data in dartvel_data beside '
          'itself, in SQLite unless DATABASE_URL is set.',
      ...compiled.lines,
      ...assets.lines,
    ],
  );
}

/// Whether the native server library at [path] can load code units: the
/// build splits the backend only when the library it embeds can load what
/// it splits off.
bool dvServerLibraryLoadsUnits(String path) {
  try {
    return DynamicLibrary.open(path).providesSymbol('aw_units_load');
  } on Object {
    return false;
  }
}
