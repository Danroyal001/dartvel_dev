// `dartvel symbols upload`: sending a collected bundle to the crash backend.
//
// Driven against the backend's own ingest through an in-process transport,
// so the paths, headers and ordering the CLI sends are the ones the endpoint
// accepts -- not two programs agreeing with their own idea of each other.
// Shape tests would pass an uploader that sends a bundle the backend refuses.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/symbols_bundle.dart';
import 'package:dartvel_cli/src/build/symbols_upload.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String token = 'upload-token-0123456789abcdef';

void main() {
  late Directory root;
  late DVMemorySymbolRepository repository;
  late DVSymbolIngest ingest;
  late List<DVHttpRequest> sent;
  late List<String> log;
  late String bundle;

  /// The backend, as an HTTP transport: the request a client makes, answered
  /// by the ingest the generated route would call.
  DVHttpSend backend({Map<int, int>? failFirst}) {
    final Map<int, int> failures = <int, int>{...?failFirst};
    return (DVHttpRequest request) async {
      sent.add(request);
      final int attempt = sent.length;
      final int? status = failures.remove(attempt);
      if (status != null) return DVHttpResponse(statusCode: status, body: '{}');
      final List<String> segments = request.url.pathSegments;
      // /api/_dartvel/symbols/<release>/<file>
      final DVSymbolIngestResult result = await ingest.accept(
        release: Uri.decodeComponent(segments[segments.length - 2]),
        name: segments.last,
        body: request.body,
        authorization: request.headers['authorization'],
        sha256: request.headers[DVSymbolIngest.checksumHeader],
      );
      return DVHttpResponse(
          statusCode: result.status, body: jsonEncode(result.toJson()));
    };
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dv_symbols_upload_');
    repository = DVMemorySymbolRepository();
    ingest = DVSymbolIngest(
        repository: repository, token: () async => token, log: (String _) {});
    sent = <DVHttpRequest>[];
    log = <String>[];

    final File debugInfo =
        File(p.join(root.path, 'build', 'debug-info', 'app.android-arm64.symbols'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(<int>[1, 2, 3]);
    final File mapping = File(p.join(
        root.path, 'build', 'app', 'outputs', 'mapping', 'release', 'mapping.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('com.example.A -> a.A:\n');
    final DateTime started = DateTime.now().subtract(const Duration(minutes: 5));
    debugInfo.setLastModifiedSync(DateTime.now());
    mapping.setLastModifiedSync(DateTime.now());
    bundle = dvCollectAndroidSymbols(
      root: root.path,
      release: '1.4.0+12',
      builtSince: started,
      buildIdOf: (List<int> _) => 'abc',
    ).directory;
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<DVSymbolUploadResult> upload({
    String origin = 'https://api.example.com',
    String? withToken = token,
    DVHttpSend? transport,
  }) =>
      dvUploadSymbols(
        bundleDirectory: bundle,
        origin: Uri.parse(origin),
        apiBasePath: '/api',
        token: withToken,
        transport: transport ?? backend(),
        log: log.add,
        pause: (Duration _) async {},
      );

  test('a bundle goes up file by file and the manifest last, and the backend '
      'accepts the release', () async {
    final DVSymbolUploadResult result = await upload();
    expect(result.ok, isTrue, reason: result.problem);
    final List<String> names =
        sent.map((DVHttpRequest r) => r.url.pathSegments.last).toList();
    // The order of the files is nobody's business; the manifest being last is
    // what makes the release complete only once every file is there.
    expect(names.take(2).toSet(),
        <String>{'app.android-arm64.symbols', 'mapping.txt'});
    expect(names.last, 'manifest.json');
    expect(await repository.hasRelease('1.4.0+12'), isTrue);
    expect(await repository.readFile('1.4.0+12', 'mapping.txt'), isNotNull);
  });

  test('every request is a PUT to the symbols path with the token and the '
      'checksum', () async {
    await upload();
    for (final DVHttpRequest request in sent) {
      expect(request.method, 'PUT');
      expect(request.url.path, startsWith('/api/_dartvel/symbols/1.4.0%2B12/'));
      expect(request.headers['authorization'], 'Bearer $token');
      expect(request.headers[DVSymbolIngest.checksumHeader],
          dvSymbolSha256(request.body));
    }
  });

  test('a wrong token stops at the first file and says so', () async {
    final DVSymbolUploadResult result = await upload(withToken: 'wrong-token-value');
    expect(result.ok, isFalse);
    expect(result.problem, contains('401'));
    expect(result.problem, contains('DARTVEL_SYMBOLS_TOKEN'));
    expect(sent, hasLength(1));
  });

  test('no token at all is refused before anything is sent', () async {
    final DVSymbolUploadResult result = await upload(withToken: null);
    expect(result.ok, isFalse);
    expect(result.problem, contains('DARTVEL_SYMBOLS_TOKEN'));
    expect(sent, isEmpty);
  });

  test('the token is never printed or put in a problem message', () async {
    await upload();
    await upload(withToken: 'wrong-token-value');
    for (final String line in log) {
      expect(line, isNot(contains(token)));
      expect(line, isNot(contains('wrong-token-value')));
    }
  });

  test('cleartext to another machine is refused, so the token is not sent '
      'across the open network', () async {
    final DVSymbolUploadResult result =
        await upload(origin: 'http://api.example.com');
    expect(result.ok, isFalse);
    expect(sent, isEmpty);
  });

  test('http to this machine is allowed, for a local backend', () async {
    expect((await upload(origin: 'http://localhost:8080')).ok, isTrue);
  });

  test('a busy backend is retried, a refusal is not', () async {
    final DVSymbolUploadResult retried =
        await upload(transport: backend(failFirst: <int, int>{1: 503, 2: 429}));
    expect(retried.ok, isTrue);
    expect(sent.length, greaterThan(3));

    sent.clear();
    repository = DVMemorySymbolRepository();
    ingest = DVSymbolIngest(
        repository: repository, token: () async => token, log: (String _) {});
    final DVSymbolUploadResult refused =
        await upload(transport: backend(failFirst: <int, int>{1: 422}));
    expect(refused.ok, isFalse);
    expect(sent, hasLength(1));
  });

  test('gives up after a few attempts rather than hanging', () async {
    final DVSymbolUploadResult result = await upload(
        transport: (DVHttpRequest r) async {
      sent.add(r);
      return const DVHttpResponse(statusCode: 503, body: '');
    });
    expect(result.ok, isFalse);
    expect(sent.length, lessThanOrEqualTo(4));
  });

  test('a bundle directory with no manifest is not uploaded', () async {
    File(p.join(bundle, 'manifest.json')).deleteSync();
    final DVSymbolUploadResult result = await upload();
    expect(result.ok, isFalse);
    expect(sent, isEmpty);
  });

  test('a file the manifest lists but the directory lacks is caught before '
      'the first byte is sent', () async {
    File(p.join(bundle, 'mapping.txt')).deleteSync();
    final DVSymbolUploadResult result = await upload();
    expect(result.ok, isFalse);
    expect(result.problem, contains('mapping.txt'));
    expect(sent, isEmpty);
  });
}
