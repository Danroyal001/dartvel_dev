import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import '../generators/routes_generator.dart';
import '../utils/logger.dart';

class WatchCommand extends Command<void> {
  @override
  final String name = 'watch';

  @override
  String get description =>
      'Watch for file changes and regenerate routes/config.${aliases.isEmpty ? '' : ' (Aliases: ${aliases.join(', ')})'}';

  @override
  final List<String> aliases = ['hotreload'];

  @override
  Future<void> run() async {
    final root = Directory.current.path;
    final pagesDir = p.join(root, 'lib', 'pages');
    final backendDir = p.join(root, 'lib', 'backend');
    final envFiles = ['.env', '.env.local'];

    Logger.log('👀 Watching for changes...');
    Logger.log('  Pages: $pagesDir');
    Logger.log('  Backend: $backendDir');
    Logger.log('  Env: ${envFiles.join(', ')}');
    Logger.log('');
    Logger.log('Press Ctrl+C to stop');

    // Initial generation
    await _regenerate();

    // Watch directories
    final watchers = <Watcher>[];

    if (Directory(pagesDir).existsSync()) {
      watchers.add(DirectoryWatcher(pagesDir));
    }

    if (Directory(backendDir).existsSync()) {
      watchers.add(DirectoryWatcher(backendDir));
    }

    for (final envFile in envFiles) {
      final file = File(p.join(root, envFile));
      if (file.existsSync()) {
        watchers.add(FileWatcher(file.path));
      }
    }

    // Debounce mechanism
    Timer? debounceTimer;
    final debounceDelay = const Duration(milliseconds: 500);

    for (final watcher in watchers) {
      watcher.events.listen((event) {
        debounceTimer?.cancel();
        debounceTimer = Timer(debounceDelay, () async {
          Logger.log('');
          Logger.log('📝 Change detected: ${event.path}');
          await _regenerate();
        });
      });
    }

    // Keep running
    await Future<void>.error('Interrupted');
  }

  Future<void> _regenerate() async {
    try {
      Logger.log('🔄 Regenerating routes...');
      await generate();
      Logger.log('✅ Done');
    } catch (e) {
      Logger.log('❌ Error: $e');
    }
  }
}
