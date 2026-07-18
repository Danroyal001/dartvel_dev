import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart';
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

    try {
      // Use dartvel_shelf to serve static files at root
      final server = await serve(
        (request) async {
          // Fallback handler - SPA files are handled automatically by spaRoot
          return Response.text('Not found', status: 404);
        },
        host: host,
        port: port,
        spaRoot: buildDir.path,
        compression: true,
      );

      Logger.log('✅ Server started successfully');
      Logger.log('');

      // Keep server running
      await ProcessSignal.sigint.watch().first;

      Logger.log('\n🛑 Shutting down server...');
      unawaited(server.stop());
    } catch (e) {
      Logger.log('❌ Failed to start server: $e');
      exit(1);
    }
  }
}
