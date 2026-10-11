// The HTTP face of the symbols ingest: `PUT /_dartvel/symbols/<release>/<file>`.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/http.dart';
import 'package:test/test.dart';

const String secret = 'endpoint-token-0123456789abcdef';

void main() {
  late DVMemorySymbolRepository repo;
  late DVSymbolIngest ingest;

  setUp(() {
    repo = DVMemorySymbolRepository();
    ingest = DVSymbolIngest(
        repository: repo, token: () async => secret, log: (String _) {});
  });

  Request put(
    String body, {
    Map<String, String> params = const <String, String>{
      'release': '1.4.0%2B12',
      'name': 'mapping.txt',
    },
    String? authorization = 'Bearer $secret',
    String? sha,
    String method = 'PUT',
  }) =>
      Request(
        method: method,
        url: Uri.parse('https://api.example.com/api/_dartvel/symbols/x/y'),
        headers: Headers({
          if (authorization != null) 'authorization': authorization,
          DVSymbolIngest.checksumHeader: sha ?? dvSymbolSha256(utf8.encode(body)),
        }),
        bodyStream: Stream<List<int>>.value(utf8.encode(body)),
        params: params,
      );

  Future<Map<String, Object?>> json(Response response) async =>
      jsonDecode(utf8.decode(await response.body!.bytes())) as Map<String, Object?>;

  test('stores the file under the decoded release', () async {
    final Response response = await DVSymbolEndpoints.put(put('map'), ingest);
    expect(response.status, 200);
    expect((await json(response))['stored'], true);
    expect(utf8.decode((await repo.readFile('1.4.0+12', 'mapping.txt'))!), 'map');
  });

  test('answers a bad token with 401 and the same body shape', () async {
    final Response response = await DVSymbolEndpoints.put(
        put('map', authorization: 'Bearer nope'), ingest);
    expect(response.status, 401);
    expect((await json(response))['stored'], false);
  });

  test('refuses a body larger than the ingest accepts without reading it all',
      () async {
    final DVSymbolIngest small = DVSymbolIngest(
        repository: repo,
        token: () async => secret,
        maxFileBytes: 4,
        log: (String _) {});
    final Response response =
        await DVSymbolEndpoints.put(put('far too large'), small);
    expect(response.status, 413);
  });

  test('a release that is not valid percent-encoding is a 400, not a crash',
      () async {
    final Response response = await DVSymbolEndpoints.put(
        put('x', params: <String, String>{'release': '%zz', 'name': 'a.txt'}),
        ingest);
    expect(response.status, 400);
  });

  test('a method other than PUT is 405 naming PUT', () async {
    final Response response =
        await DVSymbolEndpoints.put(put('x', method: 'GET'), ingest);
    expect(response.status, 405);
    expect(response.headers.get('allow'), 'PUT');
  });

  test('the answer never carries the token or the body', () async {
    final Response response = await DVSymbolEndpoints.put(
        put('secret-mapping-contents', authorization: 'Bearer wrong-$secret'),
        ingest);
    final String text = jsonEncode(await json(response));
    expect(text, isNot(contains(secret)));
    expect(text, isNot(contains('secret-mapping-contents')));
  });
}
