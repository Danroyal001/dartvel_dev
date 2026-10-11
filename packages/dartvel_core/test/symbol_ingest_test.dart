// The backend's side of `dartvel symbols upload`.
//
// The endpoint writes files supplied by a stranger into a directory the
// backend later parses (a mapping, an ELF), so the order of its checks is the
// whole of its safety: who is asking first, then whether the names are safe
// to write, then whether the bytes are the ones the uploader meant. A symbols
// directory an attacker can write into is a crash reporter that shows
// whatever stack the attacker likes.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String secret = 'symbols-token-0123456789abcdef';

void main() {
  late DVMemorySymbolRepository repo;
  late DateTime now;

  DVSymbolIngest ingest({String? token = secret, int maxFileBytes = 1024}) =>
      DVSymbolIngest(
        repository: repo,
        token: () async => token,
        maxFileBytes: maxFileBytes,
        clock: () => now,
        log: (String _) {},
      );

  Future<DVSymbolIngestResult> put(
    DVSymbolIngest endpoint, {
    String release = '1.0.0',
    String name = 'mapping.txt',
    String content = 'mapping',
    String? authorization = 'Bearer $secret',
    String? sha,
    String source = '203.0.113.7',
  }) =>
      endpoint.accept(
        release: release,
        name: name,
        body: utf8.encode(content),
        authorization: authorization,
        sha256: sha ?? dvSymbolSha256(utf8.encode(content)),
        source: source,
      );

  setUp(() {
    repo = DVMemorySymbolRepository();
    now = DateTime.utc(2026, 10, 11, 12);
  });

  group('who is asking', () {
    test('a file with the right token is stored', () async {
      final DVSymbolIngestResult result = await put(ingest());
      expect(result.outcome, DVSymbolIngestOutcome.stored);
      expect(result.status, 200);
      expect(utf8.decode((await repo.readFile('1.0.0', 'mapping.txt'))!), 'mapping');
    });

    test('no token, a wrong token and a malformed header are all 401, '
        'and store nothing', () async {
      for (final String? header in <String?>[
        null,
        '',
        'Bearer ',
        'Bearer wrong',
        'Bearer ${secret}x',
        'Bearer ${secret.substring(1)}',
        'Basic $secret',
        secret,
      ]) {
        final DVSymbolIngestResult result =
            await put(ingest(), authorization: header);
        expect(result.outcome, DVSymbolIngestOutcome.unauthorized,
            reason: '$header');
        expect(result.status, 401);
      }
      expect(await repo.readFile('1.0.0', 'mapping.txt'), isNull);
    });

    test('with no token configured the endpoint does not exist', () async {
      // Not 401: an endpoint that says "send a token" tells a scanner it is
      // there, and one that has no token set cannot be used by anybody.
      final DVSymbolIngestResult result = await put(ingest(token: null));
      expect(result.outcome, DVSymbolIngestOutcome.notConfigured);
      expect(result.status, 404);
      expect(await repo.readFile('1.0.0', 'mapping.txt'), isNull);
    });

    test('an empty configured token is no token', () async {
      expect((await put(ingest(token: ''), authorization: 'Bearer ')).outcome,
          DVSymbolIngestOutcome.notConfigured);
    });

    test('a source that keeps failing is limited, even with the right token '
        'afterwards', () async {
      final DVSymbolIngest endpoint = ingest();
      for (int i = 0; i < 20; i++) {
        await put(endpoint, authorization: 'Bearer guess$i');
      }
      final DVSymbolIngestResult blocked = await put(endpoint);
      expect(blocked.outcome, DVSymbolIngestOutcome.limited);
      expect(blocked.status, 429);

      // Another address is unaffected, and the window ends.
      expect((await put(endpoint, source: '198.51.100.1')).outcome,
          DVSymbolIngestOutcome.stored);
      now = now.add(const Duration(hours: 1, minutes: 1));
      expect((await put(endpoint)).outcome, DVSymbolIngestOutcome.stored);
    });

    test('a good upload does not count against the source', () async {
      final DVSymbolIngest endpoint = ingest();
      for (int i = 0; i < 40; i++) {
        expect((await put(endpoint, name: 'f$i.txt')).outcome,
            DVSymbolIngestOutcome.stored);
      }
    });
  });

  group('what is written', () {
    test('a release or file name that could leave the directory is refused',
        () async {
      for (final (String release, String name) in <(String, String)>[
        ('..', 'mapping.txt'),
        ('a/b', 'mapping.txt'),
        ('1.0.0', '../mapping.txt'),
        ('1.0.0', 'a/b'),
        ('1.0.0', '.env'),
        ('', 'mapping.txt'),
      ]) {
        final DVSymbolIngestResult result =
            await put(ingest(), release: release, name: name);
        expect(result.outcome, DVSymbolIngestOutcome.invalid,
            reason: '$release/$name');
        expect(result.status, 400);
      }
    });

    test('a file over the limit is refused', () async {
      final DVSymbolIngestResult result =
          await put(ingest(maxFileBytes: 8), content: 'x' * 9);
      expect(result.outcome, DVSymbolIngestOutcome.tooLarge);
      expect(result.status, 413);
      expect(await repo.readFile('1.0.0', 'mapping.txt'), isNull);
    });

    test('bytes that are not the ones the uploader hashed are refused',
        () async {
      final DVSymbolIngestResult result =
          await put(ingest(), sha: dvSymbolSha256(utf8.encode('other')));
      expect(result.outcome, DVSymbolIngestOutcome.checksumMismatch);
      expect(result.status, 422);
      expect(await repo.readFile('1.0.0', 'mapping.txt'), isNull);
    });

    test('an upload with no checksum is refused: a cut-short body must not '
        'become a mapping', () async {
      final DVSymbolIngestResult result = await ingest().accept(
        release: '1.0.0',
        name: 'mapping.txt',
        body: utf8.encode('mapping'),
        authorization: 'Bearer $secret',
        sha256: null,
      );
      expect(result.outcome, DVSymbolIngestOutcome.checksumMismatch);
    });
  });

  group('the manifest', () {
    DVSymbolsManifest manifestFor(String release, Map<String, String> files) =>
        DVSymbolsManifest(
          release: release,
          createdAt: DateTime.utc(2026, 10, 11),
          files: <DVSymbolFile>[
            for (final MapEntry<String, String> e in files.entries)
              DVSymbolFile(
                name: e.key,
                kind: DVSymbolKind.r8Mapping,
                sha256: dvSymbolSha256(utf8.encode(e.value)),
                bytes: utf8.encode(e.value).length,
              ),
          ],
        );

    Future<DVSymbolIngestResult> putManifest(
      DVSymbolIngest endpoint,
      DVSymbolsManifest manifest, {
      String? release,
    }) =>
        put(endpoint,
            release: release ?? manifest.release,
            name: DVSymbolsManifest.fileName,
            content: jsonEncode(manifest.toJson()));

    test('completes the release once every file it lists has arrived', () async {
      final DVSymbolIngest endpoint = ingest();
      await put(endpoint);
      final DVSymbolIngestResult result = await putManifest(
          endpoint, manifestFor('1.0.0', <String, String>{'mapping.txt': 'mapping'}));
      expect(result.outcome, DVSymbolIngestOutcome.stored);
      expect(await repo.hasRelease('1.0.0'), isTrue);
    });

    test('is refused while a listed file is missing', () async {
      final DVSymbolIngestResult result = await putManifest(
          ingest(), manifestFor('1.0.0', <String, String>{'mapping.txt': 'mapping'}));
      expect(result.outcome, DVSymbolIngestOutcome.incomplete);
      expect(result.status, 422);
      expect(await repo.hasRelease('1.0.0'), isFalse);
    });

    test('is refused when a listed file differs from what was uploaded',
        () async {
      final DVSymbolIngest endpoint = ingest();
      await put(endpoint, content: 'mapping');
      final DVSymbolIngestResult result = await putManifest(endpoint,
          manifestFor('1.0.0', <String, String>{'mapping.txt': 'different'}));
      expect(result.outcome, DVSymbolIngestOutcome.incomplete);
    });

    test('must name the release it is uploaded under', () async {
      final DVSymbolIngest endpoint = ingest();
      await put(endpoint, release: '2.0.0');
      final DVSymbolIngestResult result = await putManifest(
        endpoint,
        manifestFor('1.0.0', <String, String>{'mapping.txt': 'mapping'}),
        release: '2.0.0',
      );
      expect(result.outcome, DVSymbolIngestOutcome.invalid);
      expect(await repo.hasRelease('2.0.0'), isFalse);
    });

    test('that is not a manifest is invalid', () async {
      final DVSymbolIngestResult result = await put(ingest(),
          name: DVSymbolsManifest.fileName, content: 'not json');
      expect(result.outcome, DVSymbolIngestOutcome.invalid);
    });
  });

  test('a failure is never answered with what was sent', () async {
    final DVSymbolIngestResult result =
        await put(ingest(), authorization: 'Bearer wrong-$secret');
    expect(jsonEncode(result.toJson()), isNot(contains(secret)));
  });
}
