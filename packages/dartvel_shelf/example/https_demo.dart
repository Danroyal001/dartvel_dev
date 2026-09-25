// HTTPS, with HTTP/2 negotiated by ALPN.
//
//   make gen-certs            # or scripts/generate_dev_certs.sh
//   dart run example/https_demo.dart
//
//   curl -k https://127.0.0.1:8443/hello              # HTTP/2
//   curl -k --http1.1 https://127.0.0.1:8443/hello    # HTTP/1.1
//
// cert.pem and key.pem are read from the working directory.
import 'dart:io';

import 'package:dartvel_shelf/dartvel_shelf.dart';

Future<void> main() async {
  final router = Router()
    ..get('/hello', (req) async => Response.text('Hello over TLS\n'));

  final server = await serve(
    router.call,
    host: '127.0.0.1',
    port: 8443,
    tls: TlsConfig(
      certPem: await File('cert.pem').readAsString(),
      keyPem: await File('key.pem').readAsString(),
    ),
  );
  stdout.writeln('Listening on https://${server.host}:${server.port}');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
  exit(0);
}
