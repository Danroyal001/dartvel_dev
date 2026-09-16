/// The OTA workflow's patch source: DVShorebirdPatchSource over HTTP, and
/// publishing into it.
///
///   dart run tool/ci/ota_patch_server.dart publish <store> <app> <release>
///       <platform> <arch> <diff> <patched-sha256>
///   dart run tool/ci/ota_patch_server.dart serve <store> <port>
///
/// Run from the repository root, which resolves dartvel_core.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVShorebirdPatchSource, DVShorebirdPatchTarget;

Future<void> main(List<String> args) async {
  switch (args) {
    case ['publish', final store, final app, final release, final platform,
        final arch, final diff, final hash]:
      final patch = DVShorebirdPatchSource(store).publish(
        DVShorebirdPatchTarget(
          appId: app,
          releaseVersion: release,
          platform: platform,
          arch: arch,
        ),
        diff: File(diff).readAsBytesSync(),
        patchedHash: hash,
      );
      stdout.writeln('published patch ${patch.number} for $app $release '
          '$platform $arch');
    case ['serve', final store, final port]:
      final source = DVShorebirdPatchSource(store);
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        int.parse(port),
      );
      stdout.writeln('patch source on :${server.port}');
      await for (final HttpRequest request in server) {
        stdout.writeln('${request.method} ${request.uri} '
            'range=${request.headers.value('range')}');
        if (!await source.handle(request, prefix: '/updates')) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      }
    default:
      stderr.writeln('usage: publish <store> <app> <release> <platform> '
          '<arch> <diff> <sha256> | serve <store> <port>');
      exit(64);
  }
}
