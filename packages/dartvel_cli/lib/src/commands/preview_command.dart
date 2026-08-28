import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import '../build/web_server.dart';

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

    // `dartvel build web-server` writes dartvel_routes.json instead of
    // prerendering a file per route, and deletes the static pages an earlier
    // static build left behind so they cannot shadow the live ones. Serving
    // that build as plain files therefore hands back one shell for every URL,
    // with no per-route title, canonical or crawler-visible text -- which is
    // the whole difference between the two targets.
    final manifest = File(p.join(buildDir.path, 'dartvel_routes.json'));
    final serverRendered = manifest.existsSync();

    try {
      final HttpServer server;
      if (serverRendered) {
        Logger.log('   Rendering each route on request '
            '(dartvel_routes.json present).');
        server = await shelf_io.serve(
          dvWebServerHandler(webRoot: buildDir.path),
          host,
          port,
        );
      } else {
        server = await shelf_io.serve(
          createStaticHandler(buildDir.path,
              defaultDocument: 'index.html', listDirectories: false),
          host,
          port,
        );
      }

      Logger.log('✅ Server started successfully');
      Logger.log('');

      // Keep server running
      await ProcessSignal.sigint.watch().first;

      Logger.log('\n🛑 Shutting down server...');
      unawaited(server.close());
    } catch (e) {
      Logger.log('❌ Failed to start server: $e');
      exit(1);
    }
  }
}
