// Tests for Studio's media library: storage-backed media grid, upload,
// search, filter, file serving and delete, with server documents.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Object? json,
  Map<String, String>? headers,
}) =>
    Request(
      method: method,
      url: Uri.parse(
          'http://localhost:8080${path.startsWith('/') ? '' : '/'}$path'),
      headers: Headers(<String, String>{
        if (json != null) 'content-type': 'application/json',
        'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
        ...?headers,
      }),
      bodyStream: json == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
    );

Future<String> _text(Response response) async =>
    utf8.decode(await response.body!.bytes());

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(await _text(response)) as Map).cast<String, Object?>();

void main() {
  group('media screen specification', () {
    test('dvStudioScreens includes media', () {
      final DVStudioScreenSpec? spec = dvStudioScreenFor('media');
      expect(spec, isNotNull);
      expect(spec!.id, 'media');
      expect(spec.label, 'Media');
    });

    test('dvStudioScreenAliases resolves assets to media', () {
      final DVStudioScreenSpec? spec = dvStudioScreenFor('assets');
      expect(spec, isNotNull);
      expect(spec!.id, 'media');
    });

    test('media screen document renders heading and summary', () {
      final DVStudioTarget? target = dvStudioTargetFor('/__studio/media', mount: '/__studio');
      expect(target, isNotNull);
      final DVStudioDocument doc = dvStudioDocumentFor(
        target!,
        mount: '/__studio',
        data: const DVStudioProjectData(),
      );
      expect(doc.heading, 'Media');
      expect(doc.html, contains('<h1>Media</h1>'));
      expect(doc.text, contains('Media'));
    });

    test('media target document renders file heading and parent crumb', () {
      final DVStudioTarget? target = dvStudioTargetFor('/__studio/media/hero.png', mount: '/__studio');
      expect(target, isNotNull);
      expect(target!.screen.id, 'media');
      expect(target.objectName, 'hero.png');

      final DVStudioDocument doc = dvStudioDocumentFor(
        target,
        mount: '/__studio',
        data: const DVStudioProjectData(),
        models: const <DVStudioModelSpec>[],
      );
      expect(doc.heading, 'hero.png');
      expect(doc.html, contains('<h1>hero.png</h1>'));
      expect(doc.html, contains('href="/__studio/media"'));
    });
  });

  group('media API', () {
    late DVMemoryFileStorageAdapter storage;
    late MemoryDVDatabaseAdapter database;
    late DVStudioApi api;

    setUp(() {
      storage = DVMemoryFileStorageAdapter();
      database = MemoryDVDatabaseAdapter();
      api = DVStudioApi(
        database: database,
        storage: storage,
      );
    });

    test('GET api/media returns empty list initially', () async {
      final Response response = await api.respond(_request('GET', 'api/media'), 'media');
      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);
      expect(body['files'], isEmpty);
      expect(body['total'], 0);
    });

    test('POST api/media uploads a file, notes activity, and GET api/media returns it', () async {
      final List<int> sampleBytes = utf8.encode('Hello Dartvel Media');
      final String base64Data = base64Encode(sampleBytes);

      final Response uploadResponse = await api.respond(
        _request('POST', 'api/media', json: <String, Object?>{
          'name': 'greeting.txt',
          'bytes': base64Data,
          'mimeType': 'text/plain',
        }),
        'media',
      );
      expect(uploadResponse.status, 201);
      final Map<String, Object?> uploaded = await _json(uploadResponse);
      expect(uploaded['name'], 'greeting.txt');
      expect(uploaded['mimeType'], 'text/plain');
      expect(uploaded['size'], sampleBytes.length);
      final String key = '${uploaded['key']}';
      expect(key, startsWith('media/'));

      // File bytes stored in storage
      expect(await storage.exists(key), isTrue);
      expect(await storage.get(key), sampleBytes);

      // Activity logged
      final DVStudioOverview ov = await api.overview();
      expect(ov.recent.any((DVStudioActivity a) => a.kind == 'media' && a.action == 'uploaded'), isTrue);

      // GET api/media lists the file
      final Response listResponse = await api.respond(_request('GET', 'api/media'), 'media');
      expect(listResponse.status, 200);
      final Map<String, Object?> listBody = await _json(listResponse);
      expect((listBody['files']! as List).length, 1);
      expect(listBody['total'], 1);
    });

    test('GET api/media/file serves the raw file bytes', () async {
      const String content = 'image png binary content simulation';
      final List<int> bytes = utf8.encode(content);
      await storage.put('media/logo.png', bytes, contentType: 'image/png');

      final Response fileResponse = await api.respond(
        _request('GET', 'api/media/file?key=media/logo.png'),
        'media/file',
      );
      expect(fileResponse.status, 200);
      expect(fileResponse.headers.get('content-type'), 'image/png');
      expect(await fileResponse.body!.bytes(), bytes);
    });

    test('GET api/media filters by search query and type', () async {
      await api.respond(
        _request('POST', 'api/media', json: <String, Object?>{
          'name': 'banner.png',
          'bytes': base64Encode(<int>[1, 2, 3]),
          'mimeType': 'image/png',
        }),
        'media',
      );
      await api.respond(
        _request('POST', 'api/media', json: <String, Object?>{
          'name': 'intro.mp4',
          'bytes': base64Encode(<int>[4, 5, 6]),
          'mimeType': 'video/mp4',
        }),
        'media',
      );

      // Search matching
      final Response searchBanner = await api.respond(
        _request('GET', 'api/media?q=banner'),
        'media',
      );
      final Map<String, Object?> bannerBody = await _json(searchBanner);
      expect((bannerBody['files']! as List).length, 1);

      // Filter by type: image
      final Response imagesResponse = await api.respond(
        _request('GET', 'api/media?type=image'),
        'media',
      );
      final Map<String, Object?> imagesBody = await _json(imagesResponse);
      expect((imagesBody['files']! as List).length, 1);
      expect((imagesBody['files']! as List).first['name'], 'banner.png');

      // Filter by type: video
      final Response videoResponse = await api.respond(
        _request('GET', 'api/media?type=video'),
        'media',
      );
      final Map<String, Object?> videoBody = await _json(videoResponse);
      expect((videoBody['files']! as List).length, 1);
      expect((videoBody['files']! as List).first['name'], 'intro.mp4');

      // Filter by type: audio (none)
      final Response audioResponse = await api.respond(
        _request('GET', 'api/media?type=audio'),
        'media',
      );
      final Map<String, Object?> audioBody = await _json(audioResponse);
      expect(audioBody['files'], isEmpty);
    });

    test('DELETE api/media deletes the file and metadata', () async {
      final Response uploadResponse = await api.respond(
        _request('POST', 'api/media', json: <String, Object?>{
          'name': 'old.jpg',
          'bytes': base64Encode(<int>[9, 9, 9]),
          'mimeType': 'image/jpeg',
        }),
        'media',
      );
      final Map<String, Object?> uploaded = await _json(uploadResponse);
      final String key = '${uploaded['key']}';
      expect(await storage.exists(key), isTrue);

      final Response deleteResponse = await api.respond(
        _request('DELETE', 'api/media?key=${Uri.encodeQueryComponent(key)}'),
        'media',
      );
      expect(deleteResponse.status, 200);
      expect(await storage.exists(key), isFalse);

      final Response listResponse = await api.respond(_request('GET', 'api/media'), 'media');
      final Map<String, Object?> listBody = await _json(listResponse);
      expect(listBody['files'], isEmpty);
    });
  });
}
