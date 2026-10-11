/// Sending a collected symbols bundle to the crash backend.
///
/// One request per file, then the manifest, so the backend marks the release
/// complete only once every file it lists has arrived intact (it checks each
/// against the manifest's hash). A release with a partial bundle is a release
/// whose crashes are read with a mapping that is missing or from somewhere
/// else, which is worse than none.
library dartvel_cli.build.symbols_upload;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show
        DVHttpRequest,
        DVHttpResponse,
        DVHttpSend,
        DVSymbolFile,
        DVSymbolIngest,
        DVSymbolsManifest,
        dvSymbolSha256,
        dvSendHttpRequest;
import 'package:path/path.dart' as p;

/// The environment variable the token is read from. Never a command-line
/// argument: those are in `ps` and in shell history.
const String dvSymbolsTokenVariable = DVSymbolIngest.tokenSecret;

final class DVSymbolUploadResult {
  const DVSymbolUploadResult.ok({this.uploaded = 0})
      : ok = true,
        problem = null;
  const DVSymbolUploadResult.failed(String this.problem)
      : ok = false,
        uploaded = 0;

  final bool ok;
  final int uploaded;
  final String? problem;
}

/// Uploads the bundle in [bundleDirectory] to [origin].
///
/// [apiBasePath] is the backend's API prefix (`/api` unless the project
/// declares another). [token] is the bearer token; it appears in no log line
/// and no problem message.
Future<DVSymbolUploadResult> dvUploadSymbols({
  required String bundleDirectory,
  required Uri origin,
  required String apiBasePath,
  required String? token,
  DVHttpSend transport = dvSendHttpRequest,
  void Function(String line)? log,
  Future<void> Function(Duration delay)? pause,
}) async {
  void say(String line) => log?.call(line);
  final Future<void> Function(Duration) wait =
      pause ?? (Duration delay) => Future<void>.delayed(delay);

  if (token == null || token.isEmpty) {
    return const DVSymbolUploadResult.failed(
        'No symbols token. Set $dvSymbolsTokenVariable in the environment to '
        'the secret the backend was started with.');
  }
  final bool loopback =
      origin.host == 'localhost' || origin.host == '127.0.0.1' || origin.host == '::1';
  if (origin.scheme != 'https' && !(origin.scheme == 'http' && loopback)) {
    return DVSymbolUploadResult.failed(
        'Refusing to send the symbols token over ${origin.scheme} to '
        '${origin.host}. Use https.');
  }

  final File manifestFile = File(p.join(bundleDirectory, DVSymbolsManifest.fileName));
  if (!manifestFile.existsSync()) {
    return DVSymbolUploadResult.failed(
        'No ${DVSymbolsManifest.fileName} in $bundleDirectory. Build a '
        'release first, or run `dartvel symbols collect`.');
  }
  final DVSymbolsManifest manifest;
  try {
    manifest = DVSymbolsManifest.fromJson(
        (jsonDecode(manifestFile.readAsStringSync()) as Map).cast<String, Object?>());
  } on Object catch (error) {
    return DVSymbolUploadResult.failed(
        '${DVSymbolsManifest.fileName} is not a symbols manifest ($error).');
  }

  // Everything the manifest lists must be there before anything is sent, so a
  // half-uploaded release is not the result of a file missing from disk.
  for (final DVSymbolFile file in manifest.files) {
    if (!File(p.join(bundleDirectory, file.name)).existsSync()) {
      return DVSymbolUploadResult.failed(
          'The manifest lists ${file.name} and $bundleDirectory does not have '
          'it. Collect the bundle again.');
    }
  }

  final String base = origin.replace(path: '').toString().replaceAll(RegExp(r'/+$'), '');
  Uri urlFor(String name) => Uri.parse(
      '$base${_join(apiBasePath, DVSymbolIngest.path)}/'
      '${Uri.encodeComponent(manifest.release)}/${Uri.encodeComponent(name)}');

  final List<String> order = <String>[
    for (final DVSymbolFile file in manifest.files) file.name,
    DVSymbolsManifest.fileName,
  ];
  int uploaded = 0;
  for (final String name in order) {
    final List<int> bytes = File(p.join(bundleDirectory, name)).readAsBytesSync();
    say('   Uploading $name (${_size(bytes.length)})...');
    DVHttpResponse? response;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        response = await transport(DVHttpRequest(
          url: urlFor(name),
          method: 'PUT',
          headers: <String, String>{
            'authorization': 'Bearer $token',
            'content-type': 'application/octet-stream',
            DVSymbolIngest.checksumHeader: dvSymbolSha256(bytes),
          },
          body: bytes,
        ));
      } on Object catch (error) {
        // The error is the transport's, not the request's: it names the host,
        // never the headers.
        response = null;
        if (attempt == 3) {
          return DVSymbolUploadResult.failed(
              'Could not reach ${origin.host} to upload $name '
              '(${error.runtimeType}).');
        }
        await wait(Duration(seconds: attempt * 2));
        continue;
      }
      final bool busy = response.statusCode == 429 || response.statusCode >= 500;
      if (!busy) break;
      if (attempt < 3) await wait(Duration(seconds: attempt * 2));
    }
    if (response == null || !response.isSuccess) {
      final int? status = response?.statusCode;
      return DVSymbolUploadResult.failed(_explain(name, status, response?.body));
    }
    uploaded++;
  }
  say('   Symbols for ${manifest.release} uploaded: $uploaded file(s).');
  return DVSymbolUploadResult.ok(uploaded: uploaded);
}

String _explain(String name, int? status, String? body) {
  String? message;
  try {
    final Object? json = jsonDecode(body ?? '');
    if (json is Map && json['message'] is String) message = json['message'] as String;
  } on FormatException {
    // The body is not ours to quote.
  }
  final String reason = switch (status) {
    401 => 'The backend refused the token (401). It must equal the '
        '$dvSymbolsTokenVariable secret the backend runs with.',
    404 => 'The backend has no symbols endpoint (404): either '
        'dartvel.crashes.sink is not dartvel there, or $dvSymbolsTokenVariable '
        'is not set on it.',
    429 => 'The backend is rate limiting this address (429); try again later.',
    413 => 'The backend refused $name as too large (413).',
    _ => 'The backend answered $status${message == null ? '' : ': $message'}.',
  };
  return 'Uploading $name failed. $reason';
}

String _join(String a, String b) {
  final String left = a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  return '${left.startsWith('/') || left.isEmpty ? left : '/$left'}$b';
}

String _size(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
