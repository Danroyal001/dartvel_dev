import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';

class PreviewCommand extends Command<void> {
  @override
  final String name = 'preview';

  @override
  String get description => 'Preview the production build locally.';

  PreviewCommand() {
    argParser
      ..addOption('port',
          abbr: 'p', defaultsTo: '8080', help: 'Port to serve on')
      ..addOption('host', defaultsTo: '127.0.0.1', help: 'Host to bind to');
  }

  @override
  Future<void> run() async {
    final root = Directory.current.path;
    final buildDir = Directory(p.join(root, 'build', 'web'));

    if (!buildDir.existsSync()) {
      Logger.log('❌ No build found. Run: dartvel build');
      exit(1);
    }

    final port = int.parse(argResults?['port'] as String);
    final host = argResults?['host'] as String;

    Logger.log('📦 Serving build/web on http://$host:$port');
    Logger.log('Press Ctrl+C to stop');

    // Simple static file server
    final proc = await Process.start(
      'dart',
      [
        'pub',
        'global',
        'run',
        'dhttpd:dhttpd',
        '--host',
        host,
        '--port',
        port.toString(),
        '--path',
        buildDir.path,
      ],
      runInShell: true,
    );

    proc.stdout.listen((data) => stdout.add(data));
    proc.stderr.listen((data) => stderr.add(data));

    await proc.exitCode;
  }
}
