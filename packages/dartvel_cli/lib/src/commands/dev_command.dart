import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../config/dartvel_config.dart';
import '../generators/routes_generator.dart';
import '../utils/build_runner.dart';
import '../utils/linux_utils.dart';
import '../build/seo_head.dart';
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
      ..addOption('web-hostname',
          help: 'Hostname for the Flutter web-server device')
      ..addOption('web-port', help: 'Port for the Flutter web-server device')
      ..addFlag('verbose',
          abbr: 'v', defaultsTo: false, help: 'Verbose output');
  }

  @override
  Future<void> run() async {
    final root = Directory.current.path;
    await generate();

    // Ensure a dev server entry under .dart_tool
    final toolDir = Directory(p.join(root, '.dart_tool'))
      ..createSync(recursive: true);
    final devServer = File(p.join(toolDir.path, 'dartvel_dev_server.dart'));
    // Always rewrite to ensure latest runtime (switch from shelf to dartvel_shelf)
    devServer.writeAsStringSync('''
import 'dart:async';
import 'dart:io';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'dartvel_backend.g.dart' as cfg;
import 'dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  stdout.writeln('dartvel backend build: ' + (cfg.dvGenBuildId));
  final handle = await gen.startBackend(
    host: '0.0.0.0', 
    port: cfg.backendPort,
    cors: const dv.CorsOptions(
      allowAnyOrigin: true,
      allowAnyMethod: true,
      allowAnyHeader: true,
    ),
  );
  stdout.writeln('dartvel backend listening on http://' + handle.host + ':' + handle.port.toString() + cfg.apiBasePath);
  await Completer<void>().future;
}
''');

    // Start processes: build_runner + backend + flutter
    Process? buildRunnerP;
    Process? backP;
    // Kept so a restart starts the backend the same way the first start did.
    Map<String, String>? backendEnv;
    Process? flutterP;

    // Run optional user-configured builders after Dartvel's own generation.
    if (hasBuildRunnerDependency(root)) {
      Logger.log('📦 Starting build_runner watch...');
      try {
        buildRunnerP = await _spawn(
            'dart',
            ['run', 'build_runner', 'watch', '--delete-conflicting-outputs'],
            'build_runner');
      } catch (_) {
        Logger.log('⚠️  build_runner could not start');
      }
    } else {
      Logger.log('📦 No build_runner dependency declared; skipping watch.');
    }

    // Build flutter args
    final flutterArgs = <String>['run'];
    final explicitDevice = (argResults?['device'] as String?) ??
        Platform.environment['DARTVEL_DEVICE'];
    String? deviceOpt = explicitDevice;

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
    if ((explicitDevice == null || explicitDevice.isEmpty) &&
        _shouldUseWebServerByDefault(deviceOpt)) {
      deviceOpt = 'web-server';
      Logger.log(
          'Headless Linux detected; defaulting to Flutter web-server. Pass -d linux to run the desktop target.');
    }
    if (deviceOpt != null && deviceOpt.isNotEmpty) {
      flutterArgs.addAll(['-d', deviceOpt]);
    }
    // The dev server serves web/index.html straight from the project, so a
    // build-time fix would leave `dartvel run web` -- the mode a developer is
    // actually looking at when they check a layout on a phone -- laying out at
    // 980 CSS pixels and scaling down.
    if (deviceOpt != null && deviceOpt.contains('web') ||
        deviceOpt == 'chrome') {
      if (dvEnsureProjectViewport(Directory.current.path)) {
        Logger.log('Added a viewport meta to web/index.html.');
      }
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
    final webTarget = _isWebServerDevice(deviceOpt);
    final webHostname = (argResults?['web-hostname'] as String?) ??
        Platform.environment['DARTVEL_WEB_HOST'] ??
        (webTarget ? '0.0.0.0' : null);
    final webPortInput = (argResults?['web-port'] as String?) ??
        Platform.environment['DARTVEL_WEB_PORT'];
    int? webPort;
    if (webTarget) {
      webPort = await _resolveWebPort(webPortInput);
      if (webHostname != null && webHostname.isNotEmpty) {
        flutterArgs.addAll(['--web-hostname', webHostname]);
      }
      flutterArgs.addAll(['--web-port', webPort.toString()]);
      Logger.log('Dartvel web-server device selected.');
      Logger.log('Dartvel web app local URL: http://localhost:$webPort');
      final forwardedHost = Platform.environment['CODESPACE_NAME'];
      final forwardedDomain =
          Platform.environment['GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN'];
      if (forwardedHost != null &&
          forwardedHost.isNotEmpty &&
          forwardedDomain != null &&
          forwardedDomain.isNotEmpty) {
        Logger.log(
          'Dartvel web app forwarded URL: https://$forwardedHost-$webPort.$forwardedDomain',
        );
      }
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
      backendEnv = extraEnv;
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

    final config = await DartvelConfig.load(Directory(root));

    // Keep generated code, the app, the backend and the Rust runtime in step
    // while the loop runs. This used to be `dartvel watch`, a separate command
    // aliased `hotreload` that never asked Flutter to reload anything — so the
    // command that sounded like it handled reloading was the one that did not,
    // and editing a page during `dartvel dev` left the router stale.
    final watchSubscriptions = _startWatching(
      root: root,
      config: config,
      regenerate: () async {
        Logger.log('[dev] regenerating...');
        try {
          await generate();
        } catch (e) {
          Logger.log('[dev] generation failed: $e');
        }
      },
      hotReloadFlutter: () {
        // Flutter's own hot reload, not a rebuild. This is the whole reason
        // the loop feels instant.
        try {
          flutterP?.stdin.write('r');
        } catch (_) {}
      },
      restartBackend: () async {
        Logger.log('[dev] restarting backend...');
        backP?.kill();
        try {
          backP = await _spawn(
              'dart', ['run', '.dart_tool/dartvel_dev_server.dart'], 'backend',
              extraEnv: backendEnv);
        } catch (_) {
          Logger.log('[dev] backend failed to restart');
        }
      },
      rebuildNative: () async {
        Logger.log('[dev] rebuilding the native runtime...');
        final rust = p.join(root, 'packages/dartvel_shelf/rust');
        if (!Directory(rust).existsSync()) return;
        final build = await Process.run(
            'cargo', <String>['build', '--release'],
            workingDirectory: rust);
        if (build.exitCode != 0) {
          Logger.log('[dev] cargo build failed:\n${build.stderr}');
        }
      },
    );

    // Keep running until one exits
    await Future.any([
      if (buildRunnerP != null) buildRunnerP.exitCode,
      if (backP != null) backP!.exitCode,
      if (flutterP != null) flutterP.exitCode,
    ].whereType<Future<int>>());

    for (final subscription in watchSubscriptions) {
      await subscription.cancel();
    }
  }

  /// Watches the configured sources and runs only the actions a change needs.
  ///
  /// Two things keep this cheap. Events are debounced, because a single save
  /// produces several and a formatter produces more. And each path's content is
  /// digested, so a touched-but-identical file does nothing — editors save on
  /// focus loss and build tools stamp mtimes, and acting on the event rather
  /// than the content restarts a backend for a stray save.
  List<StreamSubscription<WatchEvent>> _startWatching({
    required String root,
    required DartvelConfig config,
    required Future<void> Function() regenerate,
    required void Function() hotReloadFlutter,
    required Future<void> Function() restartBackend,
    required Future<void> Function() rebuildNative,
  }) {
    final targets = dartvelWatchTargets(
      root: root,
      pagesDir: config.pagesDir,
      backendDir: config.backendDir,
      envFiles: config.envFiles,
    );

    final digests = <String, String>{};
    final subscriptions = <StreamSubscription<WatchEvent>>[];
    Timer? debounce;
    final pending = <DevChangeAction>{};

    Future<void> flush() async {
      final actions = Set<DevChangeAction>.from(pending);
      pending.clear();
      if (actions.isEmpty) return;

      // Order matters: generate before reloading, and rebuild the native
      // runtime before restarting the process that loads it.
      if (actions.contains(DevChangeAction.regenerate)) await regenerate();
      if (actions.contains(DevChangeAction.rebuildNative)) await rebuildNative();
      if (actions.contains(DevChangeAction.restartBackend)) {
        await restartBackend();
      }
      if (actions.contains(DevChangeAction.hotReloadFlutter)) {
        hotReloadFlutter();
      }
    }

    for (final target in targets) {
      final entity = target.isDirectory
          ? Directory(target.path) as FileSystemEntity
          : File(target.path);
      if (!entity.existsSync()) continue;

      final watcher = target.isDirectory
          ? DirectoryWatcher(target.path) as Watcher
          : FileWatcher(target.path);

      subscriptions.add(watcher.events.listen((WatchEvent event) {
        final digest = _digestOf(event.path);
        if (digest != null &&
            !dartvelChangeIsMeaningful(
              previousDigest: digests[event.path],
              currentDigest: digest,
            )) {
          return;
        }
        if (digest != null) digests[event.path] = digest;

        pending.addAll(target.actions);
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), () {
          unawaited(flush());
        });
      }));
    }

    return subscriptions;
  }

  /// A content digest, or null when the file cannot be read.
  ///
  /// Null means "cannot tell", and the caller treats that as a change: failing
  /// to reload is worse than reloading unnecessarily.
  String? _digestOf(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return md5.convert(file.readAsBytesSync()).toString();
    } catch (_) {
      return null;
    }
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
    unawaited(p.exitCode.then((code) {
      stdout.writeln('[$tag] exited with code $code');
    }));
    return p;
  }

  bool _isWebServerDevice(String? deviceId) {
    final normalized = deviceId?.trim().toLowerCase();
    return normalized == 'web-server' || normalized == 'web_server';
  }

  bool _shouldUseWebServerByDefault(String? deviceId) {
    final normalized = deviceId?.trim().toLowerCase();
    final onlyLinuxDevice = normalized == 'linux';
    final hasDisplay = (Platform.environment['DISPLAY'] ?? '').isNotEmpty ||
        (Platform.environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
    return Platform.isLinux && onlyLinuxDevice && !hasDisplay;
  }

  Future<int> _resolveWebPort(String? requestedPort) async {
    final parsed = int.tryParse(requestedPort ?? '');
    if (parsed != null && parsed > 0 && parsed <= 65535) {
      return parsed;
    }
    const firstPort = 8080;
    for (var port = firstPort; port < firstPort + 50; port++) {
      if (await _isPortAvailable(port)) {
        return port;
      }
    }
    return 0;
  }

  Future<bool> _isPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }
}

/// What a change under a watched path has to set off.
///
/// Separate actions rather than one "reload everything", because reloading
/// what did not change is the difference between a loop that keeps up with
/// typing and one that does not. A widget edit should not restart a server; a
/// Rust edit should not disturb the Flutter app.
enum DevChangeAction {
  /// Re-run route, client and config generation.
  regenerate,

  /// Ask the running `flutter run` to hot reload, by sending it `r`.
  ///
  /// Flutter's own mechanism, deliberately. Rebuilding to show a changed
  /// widget would throw away the thing that makes this fast.
  hotReloadFlutter,

  /// Stop and start the backend process.
  ///
  /// There is no hot reload for it: it is a separate Dart process, and the
  /// generated route table it serves is built at startup.
  restartBackend,

  /// Rebuild the Rust runtime the backend loads.
  rebuildNative,
}

/// One watched path and what changing it means.
class DevWatchTarget {
  final String path;

  /// Directories and files need different watchers, and using the wrong one
  /// fails at runtime rather than at construction.
  final bool isDirectory;

  final Set<DevChangeAction> actions;

  const DevWatchTarget({
    required this.path,
    required this.isDirectory,
    required this.actions,
  });
}

/// Everything `dartvel dev` watches, and what each change triggers.
///
/// Paths come from configuration rather than being hardcoded. The previous
/// watcher assumed `lib/pages` and `lib/backend` while the generator honoured
/// `pagesDir` and `backendDir`, so a project that moved either got a watcher
/// pointed at nothing — silently, because a watcher on a missing directory
/// simply never fires.
List<DevWatchTarget> dartvelWatchTargets({
  required String root,
  required String pagesDir,
  required String backendDir,
  required List<String> envFiles,
}) {
  return <DevWatchTarget>[
    // Dart the app runs. Flutter reloads it in place.
    DevWatchTarget(
      path: '$root/$pagesDir',
      isDirectory: true,
      actions: const <DevChangeAction>{
        DevChangeAction.regenerate,
        DevChangeAction.hotReloadFlutter,
      },
    ),
    // Dart the server runs. The generated client changes with it, so the app
    // reloads too or it will be calling signatures that no longer exist.
    DevWatchTarget(
      path: '$root/$backendDir',
      isDirectory: true,
      actions: const <DevChangeAction>{
        DevChangeAction.regenerate,
        DevChangeAction.restartBackend,
        DevChangeAction.hotReloadFlutter,
      },
    ),
    // No Dart changed, so there is nothing for Flutter to reload — but the
    // backend has the old library mapped until it restarts.
    DevWatchTarget(
      path: '$root/packages/dartvel_shelf/rust',
      isDirectory: true,
      actions: const <DevChangeAction>{
        DevChangeAction.rebuildNative,
        DevChangeAction.restartBackend,
      },
    ),
    for (final envFile in envFiles)
      DevWatchTarget(
        path: '$root/$envFile',
        isDirectory: false,
        actions: const <DevChangeAction>{
          DevChangeAction.regenerate,
          DevChangeAction.restartBackend,
          DevChangeAction.hotReloadFlutter,
        },
      ),
  ];
}

/// Whether a filesystem event represents an actual edit.
///
/// Editors save on focus loss, formatters rewrite bytes that are already
/// there, and build tools stamp mtimes. Acting on the event rather than the
/// content restarts a backend for a stray save.
///
/// A null [previousDigest] means nothing has been recorded yet, and skipping
/// then would mean never acting at all.
bool dartvelChangeIsMeaningful({
  required String? previousDigest,
  required String currentDigest,
}) {
  if (previousDigest == null) return true;
  return previousDigest != currentDigest;
}
