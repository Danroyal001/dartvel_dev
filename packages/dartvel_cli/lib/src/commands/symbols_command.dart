/// `dartvel symbols collect | upload`: the mapping and debug symbols of a
/// release build, kept per release and sent to the crash backend so a crash
/// from that release can be read.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart' show DVCrashConfig;
import 'package:dartvel_shelf/symbols.dart' show DVNativeStackSymbolizer;
import 'package:path/path.dart' as p;

import '../build/symbols_bundle.dart';
import '../build/symbols_upload.dart';
import '../utils/build_runner.dart' show readPubspecYaml;
import '../utils/logger.dart';

/// The project's release string, the crash config and the API base path, read
/// from `pubspec.yaml` in [root].
({String release, DVCrashConfig crashes, String apiBasePath}) dvSymbolsProject(
    String root) {
  final Map<Object?, Object?>? pubspec = readPubspecYaml(root);
  final Object? dartvel = pubspec?['dartvel'];
  final Map<Object?, Object?> section =
      dartvel is Map ? dartvel : const <Object?, Object?>{};
  final Object? declared = section['apiBasePath'];
  return (
    release: dvCrashReleaseFrom(pubspec?['version']),
    crashes: DVCrashConfig.parse(section['crashes']),
    apiBasePath: declared is String && declared.trim().startsWith('/')
        ? declared.trim()
        : '/api',
  );
}

/// Collects the symbols of the build that finished just now (or, with
/// [builtSince] null, of whatever the build directories hold) into
/// `build/symbols/<release>`.
DVSymbolsCollection dvCollectProjectSymbols(
  String root, {
  DateTime? builtSince,
  String? release,
}) {
  final project = dvSymbolsProject(root);
  return dvCollectAndroidSymbols(
    root: root,
    release: release ?? project.release,
    builtSince: builtSince ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    buildIdOf: DVNativeStackSymbolizer.buildIdOf,
  );
}

/// Uploads `build/symbols/<release>` to [origin] (or the project's
/// `dartvel.crashes.symbols.url`). Returns whether it succeeded, having said
/// why not.
Future<bool> dvUploadProjectSymbols(
  String root, {
  Uri? origin,
  String? release,
  String? directory,
  Map<String, String>? environment,
}) async {
  final project = dvSymbolsProject(root);
  final Uri? target = origin ?? project.crashes.symbolsUrl;
  if (target == null) {
    Logger.log('❌ No backend to upload to. Pass --url, or declare '
        'dartvel.crashes.symbols.url in pubspec.yaml.');
    return false;
  }
  final String bundle = directory ??
      p.join(root, 'build', 'symbols', release ?? project.release);
  final DVSymbolUploadResult result = await dvUploadSymbols(
    bundleDirectory: bundle,
    origin: target,
    apiBasePath: project.apiBasePath,
    token: (environment ?? Platform.environment)[dvSymbolsTokenVariable],
    log: Logger.log,
  );
  if (!result.ok) Logger.log('❌ ${result.problem}');
  return result.ok;
}

class SymbolsCommand extends Command<void> {
  @override
  final String name = 'symbols';

  @override
  final String description =
      'Collect a release build\'s mapping and debug symbols, and upload them '
      'to the crash backend.';

  SymbolsCommand() {
    addSubcommand(_CollectCommand());
    addSubcommand(_UploadCommand());
  }
}

class _CollectCommand extends Command<void> {
  @override
  final String name = 'collect';

  @override
  final String description =
      'Gather the R8 mapping, Flutter split-debug-info and native symbols of '
      'the last Android release build into build/symbols/<release>.';

  _CollectCommand() {
    argParser.addOption('release',
        help: 'The release the bundle is for. Defaults to the pubspec version.');
  }

  @override
  void run() {
    final DVSymbolsCollection result = dvCollectProjectSymbols(
      Directory.current.path,
      release: argResults?['release'] as String?,
    );
    for (final String warning in result.warnings) {
      Logger.log('⚠️  $warning');
    }
    if (result.isEmpty) {
      exitCode = 1;
      return;
    }
    Logger.log('✅ ${result.manifest.files.length} file(s) for '
        '${result.manifest.release} in ${p.relative(result.directory)}');
  }
}

class _UploadCommand extends Command<void> {
  @override
  final String name = 'upload';

  @override
  final String description =
      'Send build/symbols/<release> to the crash backend. The token is read '
      'from DARTVEL_SYMBOLS_TOKEN.';

  _UploadCommand() {
    argParser
      ..addOption('url',
          help: 'The backend\'s origin. Defaults to dartvel.crashes.symbols.url.')
      ..addOption('release',
          help: 'The release to upload. Defaults to the pubspec version.')
      ..addOption('dir', help: 'A bundle directory to upload instead.');
  }

  @override
  Future<void> run() async {
    final String? url = argResults?['url'] as String?;
    final bool ok = await dvUploadProjectSymbols(
      Directory.current.path,
      origin: url == null ? null : Uri.parse(url),
      release: argResults?['release'] as String?,
      directory: argResults?['dir'] as String?,
    );
    if (!ok) exitCode = 1;
  }
}

