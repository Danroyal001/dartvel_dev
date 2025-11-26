import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import 'package:yaml/yaml.dart';

import '../generators/routes_generator.dart';
import '../utils/logger.dart';

class WatchCommand extends Command<void> {
  @override
  final String name = 'watch';

  @override
  final String description = 'Watch for file changes and regenerate routes.';

  @override
  Future<void> run() async {
    final root = Directory.current.path;
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      Logger.log('watch: pubspec.yaml not found at project root', isError: true);
      exit(2);
    }
    final yaml = loadYaml(await pubspecFile.readAsString()) as YamlMap;
    final dv = (yaml['dartvel'] ?? {}) as YamlMap;
    final pagesDir = (dv['pagesDir'] ?? 'lib/pages').toString();
    final backendDir = (dv['backendDir'] ?? 'lib/backend').toString();

    Logger.log('dartvel watch: watching for changes (Ctrl-C to stop) ...');
    await generate();

    final watchers = <Stream<WatchEvent>>[
      DirectoryWatcher(p.join(root, pagesDir)).events,
      DirectoryWatcher(p.join(root, backendDir)).events,
      FileWatcher(p.join(root, 'pubspec.yaml')).events,
    ];

    Timer? debounce;
    void scheduleGen() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), () async {
        Logger.log('[watch] change detected → regenerating...');
        await generate();
      });
    }

    for (final s in watchers) {
      s.listen((_) => scheduleGen());
    }

    // keep running
    await Completer<void>().future;
  }
}
