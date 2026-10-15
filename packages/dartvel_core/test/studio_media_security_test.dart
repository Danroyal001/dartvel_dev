// The media library takes files from people and hands them to other people,
// so what it accepts and how it serves them is a security boundary: an SVG or
// an HTML file served from Studio's origin is script running as whoever opens
// it. And a library a restart empties is not a library.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(String method, String path, {Object? json}) => Request(
  method: method,
  url: Uri.parse('http://localhost:8080$path'),
  headers: Headers(<String, String>{
    if (json != null) 'content-type': 'application/json',
    'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
  }),
  bodyStream: json == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
);

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(utf8.decode(await response.body!.bytes())) as Map)
        .cast<String, Object?>();

/// The first bytes of a PNG, which is all a test needs of one.
final List<int> _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

void main() {
  late Directory root;
  late Directory files;
  late MemoryDVDatabaseAdapter database;
  late DVLocalFileStorageAdapter storage;
  late DVAdminServer server;

  DVAdminServer serve({int? maxMediaBytes}) => DVAdminServer(
    mount: const DVAdminMount(
      path: '/__studio',
      enabled: true,
      requiresAuth: false,
    ),
    root: root.path,
    database: database,
    storage: storage,
    maxMediaBytes: maxMediaBytes,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_studio_media_sec_');
    addTearDown(() => root.deleteSync(recursive: true));
    files = Directory('${root.path}/files');
    database = MemoryDVDatabaseAdapter();
    storage = DVLocalFileStorageAdapter(root: files.path);
    server = serve();
  });

  Future<Response> call(String method, String path, {Object? json}) async =>
      (await server.respond(
        _request(method, '/__studio/api/$path', json: json),
      ))!;

  Future<Response> upload(String name, List<int> bytes, {String? mimeType}) =>
      call('POST', 'media', json: <String, Object?>{
        'name': name,
        'bytes': base64Encode(bytes),
        'mimeType': ?mimeType,
      });

  test('a file that runs script in a browser is refused', () async {
    for (final String name in <String>[
      'logo.svg',
      'page.html',
      'page.htm',
      'app.js',
      'page.xhtml',
    ]) {
      final Response refused = await upload(name, utf8.encode('<script>'));
      expect(refused.status, 415, reason: name);
    }
    // What the browser is told it is comes from the server, not the caller.
    final Response lying =
        await upload('page.html', utf8.encode('<script>'), mimeType: 'image/png');
    expect(lying.status, 415);
    expect(await storage.list(prefix: 'media/'), isEmpty);
  });

  test('a file over the limit is refused before it is stored', () async {
    server = serve(maxMediaBytes: 16);
    final Response refused = await upload('big.png', List<int>.filled(17, 1));
    expect(refused.status, 413);
    expect((await upload('small.png', _png)).status, 201);
  });

  test('bytes that are not base64 are a bad request, not a crash', () async {
    final Response refused = await call('POST', 'media', json: <String, Object?>{
      'name': 'x.png',
      'bytes': '%%% not base64 %%%',
    });
    expect(refused.status, 400);
  });

  test('only the media library is reachable through it', () async {
    await storage.put('secrets/key.txt', utf8.encode('private'));
    expect(
      (await call('GET', 'media/file?key=secrets%2Fkey.txt')).status,
      404,
    );
    expect(
      (await call('GET', 'media/file?key=media%2F..%2Fsecrets%2Fkey.txt'))
          .status,
      404,
    );
    expect(
      (await call('DELETE', 'media?key=secrets%2Fkey.txt')).status,
      404,
    );
    expect(await storage.exists('secrets/key.txt'), isTrue);
  });

  test('a file is served so that a browser cannot run it', () async {
    final Map<String, Object?> uploaded =
        await _json(await upload('notes.txt', utf8.encode('hello')));
    final Response served = await call(
      'GET',
      'media/file?key=${Uri.encodeQueryComponent('${uploaded['key']}')}',
    );
    expect(served.status, 200);
    expect(served.headers.get('x-content-type-options'), 'nosniff');
    expect(served.headers.get('content-security-policy'), contains('sandbox'));
    expect(served.headers.get('content-disposition'), startsWith('attachment'));
    // Behind the Studio grant: no shared cache keeps it for the next person.
    expect(served.headers.get('cache-control'), contains('private'));
  });

  test('an uploaded file outlives the process that took it', () async {
    final Map<String, Object?> uploaded =
        await _json(await upload('logo.png', _png));
    server = serve();
    final Response served = await call(
      'GET',
      'media/file?key=${Uri.encodeQueryComponent('${uploaded['key']}')}',
    );
    expect(served.status, 200);
    expect(await served.body!.bytes(), _png);
  });

  test('visitors are served the library at its public address', () async {
    final Map<String, Object?> uploaded =
        await _json(await upload('logo.png', _png));
    final String publicUrl = '${uploaded['publicUrl']}';
    expect(publicUrl, startsWith('/_dartvel/media/'));

    final DVPublishedPages published = DVPublishedPages(
      database: () => database,
      media: storage,
    );
    final Response served =
        (await published.respond(_request('GET', publicUrl)))!;
    expect(served.status, 200);
    expect(served.headers.get('content-type'), 'image/png');
    expect(served.headers.get('x-content-type-options'), 'nosniff');
    expect(await served.body!.bytes(), _png);

    await storage.put('secrets/key.txt', utf8.encode('private'));
    for (final String path in <String>[
      '/_dartvel/media/../secrets/key.txt',
      '/_dartvel/media/%2E%2E/secrets/key.txt',
      '/_dartvel/media/nothing-here.png',
    ]) {
      final Response? missing = await published.respond(_request('GET', path));
      expect(missing?.status ?? 404, 404, reason: path);
    }
  });
}
