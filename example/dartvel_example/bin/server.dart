import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:dartvel_core/dartvel.dart';
import '../.dart_tool/dartvel_backend.g.dart' as cfg;
import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main() async {
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(cors())
      .addHandler(gen.buildBackendRouter());

  final server = await io.serve(handler, InternetAddress.anyIPv4, cfg.backendPort);
  stdout.writeln('dartvel backend listening on http://${server.address.host}:${server.port}${cfg.apiBasePath}');
}

