/// Fetching and unpacking the pinned PDFium archive, for the build hook.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'pdfium_release.dart';

/// Where downloaded archives are kept between builds.
Directory dvPdfiumCacheDirectory() {
  final String home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.systemTemp.path;
  return Directory('$home/.dartvel/cache/pdfium/${dvPdfiumRelease.replaceAll('/', '-')}');
}

/// The archive, from the cache if it is there and intact, else downloaded and
/// checked. A download whose sha256 differs from the pin is deleted and the
/// build fails: a library run inside the app is not taken on trust.
Future<File> dvFetchPdfium(DVPdfiumArchive archive, Directory cache) async {
  cache.createSync(recursive: true);
  final File file = File('${cache.path}/${archive.name}');
  if (file.existsSync() && dvSha256(file) == archive.sha256) return file;
  final File partial = File('${file.path}.part');
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.getUrl(archive.url);
    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('PDFium download answered ${response.statusCode}', uri: archive.url);
    }
    await response.pipe(partial.openWrite());
  } finally {
    client.close();
  }
  final String got = dvSha256(partial);
  if (got != archive.sha256) {
    partial.deleteSync();
    throw StateError('dartvel_documents: ${archive.name} has sha256 $got, not the pinned ${archive.sha256}. '
        'Not bundling it.');
  }
  partial.renameSync(file.path);
  return file;
}

String dvSha256(File file) => sha256.convert(file.readAsBytesSync()).toString();

/// Extracts [member] of [tgz] into [into] with the system tar (Linux, macOS
/// and Windows 10 and later all have one).
Future<File> dvExtract(File tgz, String member, Directory into) async {
  into.createSync(recursive: true);
  final ProcessResult result = await Process.run('tar', <String>['-xzf', tgz.path, '-C', into.path, member]);
  if (result.exitCode != 0) {
    throw StateError('dartvel_documents: could not extract $member from ${tgz.path}: ${result.stderr}');
  }
  return File('${into.path}/$member');
}
