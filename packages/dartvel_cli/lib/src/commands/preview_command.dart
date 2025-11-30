import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
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

    // Create static file handler
    final handler = createStaticHandler(
      buildDir.path,
      defaultDocument: 'index.html',
      listDirectories: false,
    );

    // Add SPA fallback for client-side routing
    final cascade = shelf.Cascade().add(handler).add((request) async {
      // Fallback to index.html for SPA routing
      final indexFile = File(p.join(buildDir.path, 'index.html'));
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        return shelf.Response.ok(
          content,
          headers: {'Content-Type': 'text/html'},
        );
      }
      return shelf.Response.notFound('Not found');
    });

    try {
      final server = await shelf_io.serve(
        cascade.handler,
        host,
        port,
      );

      Logger.log('✅ Server started successfully');
      Logger.log('');

      // Keep the server running
      await ProcessSignal.sigint.watch().first;

      Logger.log('\n🛑 Shutting down server...');
      await server.close();
    } catch (e) {
      Logger.log('❌ Failed to start server: $e');
      exit(1);
    }
  }
}
