import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class Recorder {
  final List<DVHttpRequest> requests = <DVHttpRequest>[];
  final List<DVHttpResponse> _responses;

  Recorder([List<DVHttpResponse>? responses])
      : _responses = List<DVHttpResponse>.of(
          responses ??
              const <DVHttpResponse>[
                DVHttpResponse(statusCode: 200, body: ''),
              ],
        );

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    return _responses.length == 1 ? _responses.first : _responses.removeAt(0);
  }

  DVHttpRequest get single {
    expect(requests, hasLength(1));
    return requests.single;
  }
}

const credentials = DVAwsCredentials(
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
);
final at = DateTime.utc(2026, 7, 31, 12, 34, 56);

S3FileStorageAdapter s3(
  Recorder recorder, {
  bool usePathStyle = true,
  Uri? endpoint,
}) =>
    S3FileStorageAdapter(
      bucket: 'assets',
      region: 'us-east-1',
      credentials: credentials,
      endpoint: endpoint,
      usePathStyle: usePathStyle,
      transport: recorder.send,
      now: () => at,
    );

void main() {
  group('DVMemoryFileStorageAdapter', () {
    late DVMemoryFileStorageAdapter storage;
    setUp(() => storage = DVMemoryFileStorageAdapter());

    test('round-trips bytes', () async {
      await storage.put('a.bin', <int>[1, 2, 3]);
      expect(await storage.get('a.bin'), <int>[1, 2, 3]);
    });

    test('copies on write and read, so callers cannot mutate the store',
        () async {
      final source = <int>[1, 2, 3];
      await storage.put('a.bin', source);
      source[0] = 99;
      expect(await storage.get('a.bin'), <int>[1, 2, 3]);

      (await storage.get('a.bin'))[0] = 42;
      expect(await storage.get('a.bin'), <int>[1, 2, 3]);
    });

    test('reports a missing object as not found', () async {
      await expectLater(
        storage.get('missing'),
        throwsA(isA<DVFileStorageException>()
            .having((error) => error.isNotFound, 'isNotFound', isTrue)),
      );
      expect(await storage.exists('missing'), isFalse);
    });

    test('lists sorted keys, filtered by prefix', () async {
      await storage.put('b.txt', <int>[]);
      await storage.put('a.txt', <int>[]);
      await storage.put('nested/c.txt', <int>[]);

      expect(await storage.list(), <String>['a.txt', 'b.txt', 'nested/c.txt']);
      expect(await storage.list(prefix: 'nested/'), <String>['nested/c.txt']);
    });
  });

  group('S3FileStorageAdapter', () {
    test('signs a PUT with SigV4 and sends the bytes', () async {
      final recorder = Recorder();
      await s3(recorder)
          .put('avatar.png', <int>[1, 2, 3], contentType: 'image/png');

      final request = recorder.single;
      expect(request.method, 'PUT');
      expect(
        request.url.toString(),
        'https://s3.us-east-1.amazonaws.com/assets/avatar.png',
      );
      expect(request.headers['content-type'], 'image/png');
      expect(request.headers['authorization'], startsWith('AWS4-HMAC-SHA256 '));
      expect(request.headers['authorization'], contains('/us-east-1/s3/'));
      expect(request.headers['x-amz-date'], '20260731T123456Z');
      expect(request.body, <int>[1, 2, 3]);
    });

    test('returns raw bytes from a GET rather than a decoded string', () async {
      // 0xFF is not valid UTF-8; a text-only transport would corrupt it.
      final payload = <int>[0x00, 0xFF, 0x10];
      final recorder = Recorder(<DVHttpResponse>[
        DVHttpResponse(statusCode: 200, body: '', bytes: payload),
      ]);

      expect(await s3(recorder).get('blob.bin'), payload);
    });

    test('treats a missing object as absent for exists', () async {
      final missing = Recorder(const <DVHttpResponse>[
        DVHttpResponse(statusCode: 404, body: ''),
      ]);
      expect(await s3(missing).exists('gone'), isFalse);
      expect(missing.single.method, 'HEAD');

      final present = Recorder(const <DVHttpResponse>[
        DVHttpResponse(statusCode: 200, body: ''),
      ]);
      expect(await s3(present).exists('here'), isTrue);
    });

    test('treats deleting an absent object as success', () async {
      final recorder = Recorder(const <DVHttpResponse>[
        DVHttpResponse(statusCode: 404, body: ''),
      ]);
      await expectLater(s3(recorder).delete('gone'), completes);
    });

    test('raises a typed failure for a real error', () async {
      final recorder = Recorder(const <DVHttpResponse>[
        DVHttpResponse(statusCode: 403, body: '<Error>AccessDenied</Error>'),
      ]);

      await expectLater(
        s3(recorder).get('secret'),
        throwsA(
          isA<DVFileStorageException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.operation, 'operation', 'get')
              .having((error) => error.key, 'key', 'secret')
              .having((error) => error.isNotFound, 'isNotFound', isFalse)
              .having((error) => error.responseBody, 'responseBody',
                  contains('AccessDenied')),
        ),
      );
    });

    test('uses path-style addressing by default, for R2 and MinIO', () async {
      final recorder = Recorder();
      await s3(
        recorder,
        endpoint: Uri.https('minio.internal:9000'),
      ).put('a.bin', <int>[]);

      expect(
        recorder.single.url.toString(),
        'https://minio.internal:9000/assets/a.bin',
      );
    });

    test('uses virtual-hosted addressing when asked', () async {
      final recorder = Recorder();
      await s3(recorder, usePathStyle: false).put('a.bin', <int>[]);

      expect(
        recorder.single.url.toString(),
        'https://assets.s3.us-east-1.amazonaws.com/a.bin',
      );
    });

    test('percent-encodes each key segment but keeps the separators', () async {
      final recorder = Recorder();
      await s3(recorder).put('folder name/a file.png', <int>[]);

      expect(
        recorder.single.url.path,
        '/assets/folder%20name/a%20file.png',
      );
    });

    test('rejects an empty key', () async {
      await expectLater(
        s3(Recorder()).put('', <int>[]),
        throwsArgumentError,
      );
    });

    test('lists keys from the XML response', () async {
      final recorder = Recorder(const <DVHttpResponse>[
        DVHttpResponse(
          statusCode: 200,
          body: '''
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <Contents><Key>a.txt</Key><Size>1</Size></Contents>
  <Contents><Key>nested/b.txt</Key><Size>2</Size></Contents>
</ListBucketResult>''',
        ),
      ]);

      final keys = await s3(recorder).list(prefix: 'nested/');
      expect(keys, <String>['a.txt', 'nested/b.txt']);
      expect(recorder.single.url.queryParameters['list-type'], '2');
      expect(recorder.single.url.queryParameters['prefix'], 'nested/');
    });

    test('unescapes XML entities in listed keys', () {
      expect(
        S3FileStorageAdapter.parseListKeys(
          '<Contents><Key>a&amp;b/c&lt;d&gt;.txt</Key></Contents>',
        ),
        <String>['a&b/c<d>.txt'],
      );
    });

    test('signs the body, so two different uploads differ', () async {
      Future<String> authFor(List<int> bytes) async {
        final recorder = Recorder();
        await s3(recorder).put('a.bin', bytes);
        return recorder.requests.single.headers['authorization']!;
      }

      expect(
          await authFor(<int>[1, 2, 3]), isNot(await authFor(<int>[4, 5, 6])));
    });

    test('satisfies the DVFileStorageAdapter contract', () {
      expect(s3(Recorder()), isA<DVFileStorageAdapter>());
    });
  });
}
