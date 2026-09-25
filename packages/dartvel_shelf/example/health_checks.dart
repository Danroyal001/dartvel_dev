// Health checks on the built-in /health endpoint.
//
// A Router answers GET /health itself unless you register your own route for
// it. With no checks registered it reports {"status":"up"}; each check you
// register is run on every request, and a check that reports down makes the
// endpoint answer 503.
//
// The check API lives in dartvel_core, which dartvel_shelf depends on. To
// import it from your own package, add it: `dart pub add dartvel_core`.
//
//   dart run example/health_checks.dart
//   curl -i http://127.0.0.1:8080/health
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVHealthResult;
import 'package:dartvel_core/dv.dart';
import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  DV.ObservabilityAndLogging.health.register('disk', () async {
    final tmp = Directory.systemTemp;
    return tmp.existsSync()
        ? DVHealthResult.up()
        : DVHealthResult.down('${tmp.path} is missing');
  });

  final router = Router()..get('/', (req) async => Response.text('ok\n'));
  final server = await serve(router.call, host: '127.0.0.1', port: 8080);
  stdout.writeln('Listening on http://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
