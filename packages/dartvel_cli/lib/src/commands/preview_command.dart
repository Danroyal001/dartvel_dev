import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dvs;
import 'package:path/path.dart' as p;

import '../utils/helpers.dart';
import '../utils/logger.dart';

class PreviewCommand extends Command<void> {
  @override
  final String name = 'preview';

  @override
  final String description = 'Preview the built application.';

  PreviewCommand() {
    argParser
      ..addOption('dir', defaultsTo: 'build/web', help: 'Directory to serve')
      ..addOption('host', defaultsTo: '127.0.0.1', help: 'Host to bind to')
      ..addOption('port', defaultsTo: '4321', help: 'Port to bind to');
  }

  @override
  Future<void> run() async {
    final dir = (argResults?['dir'] as String?)?.trim().isNotEmpty == true
        ? (argResults?['dir'] as String)
        : 'build/web';
    final host = (argResults?['host'] as String?)?.trim().isNotEmpty == true
        ? (argResults?['host'] as String)
        : '127.0.0.1';
    final port = asInt(argResults?['port'], 4321);

    final abs = p.normalize(p.join(Directory.current.path, dir));
    if (!Directory(abs).existsSync()) {
      Logger.log('[preview] Directory not found: $abs', isError: true);
      Logger.log('Run a build first or pass --dir to an existing folder.', isError: true);
      exit(2);
    }

    Future<dvs.Response> serveStatic(dvs.Request req) async {
      final rawPath = req.url.path;
      final rel = rawPath == '/' ? 'index.html' : rawPath.substring(1);
      final resolved = p.normalize(p.join(abs, rel));
      if (!p.isWithin(abs, resolved)) {
        return dvs.Response.text('Forbidden', status: 403);
      }
      final file = File(resolved);
      if (!file.existsSync()) {
        return dvs.Response.text('Not Found', status: 404);
      }
      final bytes = await file.readAsBytes();
      final headers = dvs.Headers();
      if (resolved.endsWith('.html')) {
        headers.set('content-type', 'text/html; charset=utf-8');
      } else if (resolved.endsWith('.css')) {
        headers.set('content-type', 'text/css; charset=utf-8');
      } else if (resolved.endsWith('.js')) {
        headers.set('content-type', 'application/javascript; charset=utf-8');
      } else if (resolved.endsWith('.json')) {
        headers.set('content-type', 'application/json; charset=utf-8');
      } else if (resolved.endsWith('.png')) {
        headers.set('content-type', 'image/png');
      } else if (resolved.endsWith('.jpg') || resolved.endsWith('.jpeg')) {
        headers.set('content-type', 'image/jpeg');
      } else if (resolved.endsWith('.svg')) {
        headers.set('content-type', 'image/svg+xml');
      } else {
        headers.set('content-type', 'application/octet-stream');
      }
      return dvs.Response(200,
          headers: headers, body: Stream<List<int>>.value(bytes));
    }

    final router = dvs.Router()
      ..get('/', serveStatic)
      ..get('/:rest(.*)', serveStatic);

    final handle = await dvs.serve(router.call, host: host, port: port);
    Logger.log('[preview] Serving $abs at http://${handle.host}:${handle.port}');
    Logger.log('[preview] Press Ctrl-C to stop.');
    await Completer<void>().future;
  }
}
