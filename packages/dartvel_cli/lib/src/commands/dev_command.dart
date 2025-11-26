import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../generators/routes_generator.dart';
import '../utils/linux_utils.dart';
import '../utils/logger.dart';

class DevCommand extends Command<void> {
  @override
  final String name = 'dev';

  @override
  String get description =>
      'Run the Dartvel development server and Flutter app.${aliases.isEmpty ? '' : ' (Aliases: ${aliases.join(', ')})'}';

  @override
  final List<String> aliases = ['run', 'start'];

  DevCommand() {
    argParser
      ..addOption('device',
          abbr: 'd', help: 'Target device id or name (prefixes allowed)')
      ..addFlag('release', defaultsTo: false, help: 'Build in release mode')
      ..addFlag('profile', defaultsTo: false, help: 'Build in profile mode')
      ..addFlag('debug', defaultsTo: false, help: 'Build in debug mode')
      ..addMultiOption('dart-define',
          help: 'Pass additional dart-defines to Flutter')
      ..addMultiOption('dart-define-from-file',
          help: 'Pass dart-define-from-file to Flutter')
      ..addOption('web-renderer',
          help: 'Select web renderer (auto, html, canvaskit)')
      ..addFlag('verbose',
          abbr: 'v', defaultsTo: false, help: 'Verbose output');
  }

  @override
  Future<void> run() async {
    final root = Directory.current.path;
    await generate();

    // Run build_runner to generate env.g.dart
    Logger.log('dartvel dev: running build_runner...');
    final buildRunner = await Process.run(
      'dart',
      ['run', 'build_runner', 'build', '--delete-conflicting-outputs'],
      runInShell: true,
      workingDirectory: root,
    );
    if (buildRunner.exitCode != 0) {
      Logger.log('ERROR: build_runner failed');
      Logger.log(buildRunner.stdout.toString());
      Logger.log(buildRunner.stderr.toString());
      exit(buildRunner.exitCode);
    }

    // Ensure a dev server entry under .dart_tool
    final toolDir = Directory(p.join(root, '.dart_tool'))
      ..createSync(recursive: true);
    final devServer = File(p.join(toolDir.path, 'dartvel_dev_server.dart'));
    // Always rewrite to ensure latest runtime (switch from shelf to dartvel_shelf)
    devServer.writeAsStringSync('''
import 'dart:async';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'dartvel_backend.g.dart' as cfg;
import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  // ignore: avoid_print
  print('dartvel backend build: ' + (cfg.dvGenBuildId));
  final handle = await gen.startBackend(
    host: '0.0.0.0', 
    port: cfg.backendPort,
    cors: const dv.CorsOptions(
      allowAnyOrigin: true,
      allowAnyMethod: true,
      allowAnyHeader: true,
    ),
  );
  // ignore: avoid_print
  print('dartvel backend listening on http://' + handle.host + ':' + handle.port.toString() + cfg.apiBasePath);
  await Completer<void>().future;
}
''');

    // Start processes: backend + flutter; add in-process file watching and stdin passthrough
    Process? backP;
    Process? flutterP;

    // Build flutter args
    final flutterArgs = <String>['run'];
    String? deviceOpt = (argResults?['device'] as String?) ??
        Platform.environment['DARTVEL_DEVICE'];

    if (deviceOpt == null || deviceOpt.isEmpty) {
      try {
        final proc = await Process.run('flutter', ['devices', '--machine'],
            runInShell: true);
        if ((proc.stdout as String).toString().trim().isNotEmpty) {
          final list = jsonDecode(proc.stdout as String) as List<Object?>;
          if (list.isEmpty) {
            Logger.log(
                '[dev] No devices found. You can pass -d chrome, -d linux, etc.');
          } else if (list.length == 1) {
            final id = (list.first as Map)['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              deviceOpt = id;
            }
          } else {
            Logger.log('Multiple devices detected. Select a device:');
            for (var i = 0; i < list.length; i++) {
              final m = list[i] as Map;
              final id = (m['id'] ?? '').toString();
              final name = (m['name'] ?? '').toString();
              final plat = (m['targetPlatform'] ?? '').toString();
              Logger.log('  [${i + 1}] $name • $id • $plat');
            }
            stdout.write('Enter number or device id (default 1): ');
            final sel = stdin.readLineSync()?.trim() ?? '';
            if (sel.isEmpty) {
              deviceOpt = (list.first as Map)['id']?.toString();
            } else {
              final n = int.tryParse(sel);
              if (n != null && n >= 1 && n <= list.length) {
                deviceOpt = (list[n - 1] as Map)['id']?.toString();
              } else {
                // assume user typed device id
                deviceOpt = sel;
              }
            }
          }
        }
      } catch (_) {}
    }
    if (deviceOpt != null && deviceOpt.isNotEmpty) {
      flutterArgs.addAll(['-d', deviceOpt]);
    }
    if (argResults?['release'] == true) flutterArgs.add('--release');
    if (argResults?['profile'] == true) flutterArgs.add('--profile');
    if (argResults?['debug'] == true) flutterArgs.add('--debug');
    for (final dd
        in (argResults?['dart-define'] as List<String>? ?? const [])) {
      flutterArgs.addAll(['--dart-define', dd]);
    }
    for (final ddf in (argResults?['dart-define-from-file'] as List<String>? ??
        const [])) {
      flutterArgs.addAll(['--dart-define-from-file', ddf]);
    }
    final webRenderer = argResults?['web-renderer'] as String?;
    if (webRenderer != null && webRenderer.isNotEmpty) {
      flutterArgs.addAll(['--web-renderer', webRenderer]);
    }
    if (argResults?['verbose'] == true) flutterArgs.add('-v');

    final targetIsLinux = isLinuxDevice(deviceOpt);
    if (targetIsLinux) {
      await ensureLinuxDependencies();
    }

    Logger.log('dartvel dev: starting backend and Flutter app...');
    try {
      // Try to locate native dartvel_shelf library and pass via env for backend
      Map<String, String>? extraEnv;
      try {
        String libName;
        if (Platform.isLinux) {
          libName = 'libdartvel_shelf.so';
        } else if (Platform.isMacOS) {
          libName = 'libdartvel_shelf.dylib';
        } else if (Platform.isWindows) {
          libName = 'dartvel_shelf.dll';
        } else {
          libName = 'libdartvel_shelf.so';
        }
        final candidates = <String>[
          p.join(root, libName),
          p.normalize(p.join(root,
              '../../packages/dartvel_shelf/rust/target/release', libName)),
          p.normalize(p.join(
              root, '../packages/dartvel_shelf/rust/target/release', libName)),
          p.normalize(p.join(
              root, 'packages/dartvel_shelf/rust/target/release', libName)),
        ];
        for (final c in candidates) {
          if (File(c).existsSync()) {
            extraEnv = {'DARTVEL_SHELF_LIB': c};
            break;
          }
        }
      } catch (_) {}
      // Always add debug env that helps diagnose native crashes
      extraEnv = {
        ...?extraEnv,
        'RUST_BACKTRACE': '1',
        'MALLOC_CHECK_': '3',
      };
      backP = await _spawn(
          'dart', ['run', '.dart_tool/dartvel_dev_server.dart'], 'backend',
          extraEnv: extraEnv);
    } catch (_) {
      Logger.log('WARN: failed to start backend');
    }
    try {
      Map<String, String> flutterEnv = const {};
      if (targetIsLinux) {
        flutterEnv = await flutterEnvOverrides();
        await resetFlutterLinuxBuildArtifacts(root, flutterEnv);
      }
      flutterP = await _spawn('flutter', flutterArgs, 'flutter',
          extraEnv: flutterEnv.isEmpty ? null : flutterEnv);
    } catch (_) {
      Logger.log(
          'WARN: failed to start Flutter app. Ensure Flutter SDK is installed.');
    }

    // Wire stdin to Flutter for hot reload commands
    if (flutterP != null) {
      stdin.listen((data) {
        try {
          flutterP!.stdin.add(data);
        } catch (_) {}
      });
    }

    // Keep running until one exits
    await Future.any([
      if (backP != null) backP.exitCode,
      if (flutterP != null) flutterP.exitCode,
    ].whereType<Future<int>>());
  }

  Future<Process> _spawn(String exe, List<String> args, String tag,
      {Map<String, String>? extraEnv}) async {
    final env = <String, String>{...Platform.environment, ...?extraEnv};
    final p = await Process.start(
      exe,
      args,
      runInShell: true,
      environment: env,
      includeParentEnvironment: true,
    );
    // Prefix logs with tag
    void pipe(Stream<List<int>> s, IOSink out) {
      s
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => out.writeln('[$tag] $line'),
            onError: (e) => out.writeln('[$tag][err] $e'),
          );
    }

    pipe(p.stdout, stdout);
    pipe(p.stderr, stderr);
    p.exitCode.then((code) {
      stdout.writeln('[$tag] exited with code $code');
    });
    return p;
  }
}
