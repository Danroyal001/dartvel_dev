// The Dartvel backend sink: reports sent to the deployment's own backend,
// accepted there, and never written anywhere they should not be.
//
// The failures that look like success:
//
//  * a report whose message holds a card number, logged by the endpoint that
//    refused it or by the store that failed to keep it -- an error string
//    from a database quotes the values it could not insert;
//  * a resend after the client died between sending and marking it sent,
//    stored as a second crash;
//  * one device in a crash loop filling the table, or a failed store counting
//    against the device's budget so its retry is refused;
//  * a refusal the client treats as a failure, retrying a report the backend
//    will never accept on every launch forever -- or a 5xx it treats as
//    delivered, losing the report.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String secret = 'CARD-4111111111111111';

DVCrashReport report({
  String id = 'r1',
  String installId = 'install-1',
  String message = 'boom',
}) =>
    DVCrashReport(
      id: id,
      kind: DVCrashKind.fatal,
      errorType: 'StateError',
      message: message,
      frames: const <DVCrashFrame>[DVCrashFrame(function: 'main')],
      fingerprint: 'f',
      context: DVCrashContext(release: '1.0.0', installId: installId),
      occurredAt: DateTime.utc(2026, 9, 14),
    );

List<int> body(DVCrashReport r) => utf8.encode(jsonEncode(r.toJson()));

class _FailingRepository implements DVCrashReportRepository {
  bool failing = true;
  final DVMemoryCrashReportRepository inner = DVMemoryCrashReportRepository();

  @override
  Future<bool> put(DVCrashReport report, {required DateTime receivedAt}) {
    if (failing) {
      throw StateError('INSERT INTO dv_crash_reports failed for ${report.message}');
    }
    return inner.put(report, receivedAt: receivedAt);
  }
}

void main() {
  late List<String> logged;
  late DateTime now;

  setUp(() {
    logged = <String>[];
    now = DateTime.utc(2026, 9, 14, 9);
  });

  DVCrashIngest ingest(
    DVCrashReportRepository repository, {
    int perInstallPerHour = 3,
    int? perSourcePerHour,
    int maxBytes = 65536,
  }) =>
      DVCrashIngest(
        repository: repository,
        perInstallPerHour: perInstallPerHour,
        perSourcePerHour: perSourcePerHour,
        maxBytes: maxBytes,
        clock: () => now,
        log: logged.add,
      );

  // The per-install limit keys on an id the client writes into the report. A
  // client that writes a new one per report has a fresh budget every time,
  // so the limit that was meant to stop one device filling the table stops
  // nothing. The source is the client address the backend resolved.
  group('rate limits per source', () {
    const String source = '203.0.113.7';

    test('rotating install ids from one source stop being stored at the '
        'source budget', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngest endpoint =
          ingest(repo, perInstallPerHour: 3, perSourcePerHour: 5);

      final List<int> statuses = <int>[
        for (int i = 0; i < 12; i++)
          (await endpoint.accept(body(report(id: 'r$i', installId: 'rotated-$i')),
                  source: source))
              .status,
      ];

      expect(statuses.take(5), everyElement(201));
      expect(statuses.skip(5), everyElement(429));
      expect(repo.stored, hasLength(5));
      expect(endpoint.sourceLimited(source), 7);
    });

    test('the refusal is retryable and repeats nothing of the source or the '
        'report', () async {
      final DVCrashIngest endpoint = ingest(DVMemoryCrashReportRepository(),
          perInstallPerHour: 1, perSourcePerHour: 1);
      await endpoint.accept(body(report(id: 'a', installId: 'i-a')),
          source: source);
      final DVCrashIngestResult refused = await endpoint.accept(
          body(report(id: 'b', installId: 'i-b', message: 'paid with $secret')),
          source: source);
      await endpoint.accept(body(report(id: 'c', installId: 'i-c')),
          source: source);

      expect(refused.outcome, DVCrashIngestOutcome.sourceLimited);
      // 429 is not 2xx, so the client keeps the report for a later launch:
      // many installs behind one address are delayed, not lost.
      expect(refused.status, 429);
      final String answered = jsonEncode(refused.toJson());
      expect(answered, isNot(contains(source)));
      expect(answered, isNot(contains(secret)));
      expect(logged.where((String l) => l.contains('DV-CRASH-004')),
          hasLength(1), reason: 'once an hour per source, not per report');
      expect(logged.join('\n'), isNot(contains(source)));
      expect(logged.join('\n'), isNot(contains(secret)));
    });

    test('another source is not affected', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngest endpoint =
          ingest(repo, perInstallPerHour: 3, perSourcePerHour: 1);
      await endpoint.accept(body(report(id: 'a', installId: 'i-a')),
          source: source);
      expect(
          (await endpoint.accept(body(report(id: 'b', installId: 'i-b')),
                  source: source))
              .status,
          429);
      expect(
          (await endpoint.accept(body(report(id: 'c', installId: 'i-c')),
                  source: '198.51.100.9'))
              .status,
          201);
    });

    test('by default ten installs behind one address can each spend their '
        'whole budget', () async {
      // An office, a campus or a carrier-grade NAT is one address. The
      // default bound is ten installs at their full hourly budget -- 300
      // reports -- and a report past it is refused with 429 and sent again
      // later, not dropped.
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngest endpoint = DVCrashIngest(
          repository: repo, clock: () => now, log: logged.add);
      expect(endpoint.perSourcePerHour, 10 * endpoint.perInstallPerHour);

      for (int install = 0; install < 10; install++) {
        for (int n = 0; n < endpoint.perInstallPerHour; n++) {
          final DVCrashIngestResult result = await endpoint.accept(
              body(report(id: 'r$install-$n', installId: 'nat-$install')),
              source: source);
          expect(result.status, 201, reason: 'install $install report $n');
        }
      }
      expect(
          (await endpoint.accept(body(report(id: 'over', installId: 'nat-10')),
                  source: source))
              .status,
          429);
      expect(repo.stored, hasLength(300));
    });

    test('the default follows a raised per-install budget', () {
      expect(
          DVCrashIngest(
                  repository: DVMemoryCrashReportRepository(),
                  perInstallPerHour: 50)
              .perSourcePerHour,
          500);
    });

    test('the source budget is per hour and comes back', () async {
      final DVCrashIngest endpoint = ingest(DVMemoryCrashReportRepository(),
          perInstallPerHour: 3, perSourcePerHour: 1);
      await endpoint.accept(body(report(id: 'a', installId: 'i-a')),
          source: source);
      expect(
          (await endpoint.accept(body(report(id: 'b', installId: 'i-b')),
                  source: source))
              .status,
          429);

      now = now.add(const Duration(minutes: 61));

      expect(
          (await endpoint.accept(body(report(id: 'c', installId: 'i-c')),
                  source: source))
              .status,
          201);
    });

    test('a duplicate, a report counted per install and a failed store do not '
        'spend the source budget', () async {
      final _FailingRepository repo = _FailingRepository();
      final DVCrashIngest endpoint =
          ingest(repo, perInstallPerHour: 1, perSourcePerHour: 2);

      expect(
          (await endpoint.accept(body(report(id: 'x', installId: 'i-x')),
                  source: source))
              .status,
          503);
      repo.failing = false;
      expect(
          (await endpoint.accept(body(report(id: 'a', installId: 'i-a')),
                  source: source))
              .status,
          201);
      expect(
          (await endpoint.accept(body(report(id: 'a', installId: 'i-a')),
                  source: source))
              .status,
          200);
      expect(
          (await endpoint.accept(body(report(id: 'b', installId: 'i-a')),
                  source: source))
              .status,
          202);
      expect(
          (await endpoint.accept(body(report(id: 'c', installId: 'i-c')),
                  source: source))
              .status,
          201,
          reason: 'one report stored so far, so the second fits');
    });

    test('a report given no source is counted in the one unknown source, not '
        'left unlimited', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngest endpoint =
          ingest(repo, perInstallPerHour: 3, perSourcePerHour: 2);
      final List<int> statuses = <int>[
        for (int i = 0; i < 4; i++)
          (await endpoint.accept(body(report(id: 'u$i', installId: 'u-$i'))))
              .status,
      ];
      expect(statuses, <int>[201, 201, 429, 429]);
      expect(endpoint.sourceLimited(DVClientAddress.unknownSource), 2);
    });

    test('an IPv6 client rotating addresses in its /64 is one source',
        () async {
      addTearDown(DVClientAddress.reset);
      final DVCrashIngest endpoint = ingest(DVMemoryCrashReportRepository(),
          perInstallPerHour: 3, perSourcePerHour: 2);
      String from(String peer) => DVClientAddress.sourceOf(Request(
            method: 'POST',
            url: Uri.parse('http://app.test/api/_dartvel/crashes'),
            headers: Headers(),
            bodyStream: const Stream<List<int>>.empty(),
            peerAddress: DVPeerAddress.parse(peer),
          ));
      final List<int> statuses = <int>[
        for (int i = 1; i <= 3; i++)
          (await endpoint.accept(body(report(id: 'v$i', installId: 'v-$i')),
                  source: from('[2001:db8:44:1::$i]:5000')))
              .status,
      ];
      expect(statuses, <int>[201, 201, 429]);
    });
  });

  group('accepting a report', () {
    test('a whole report is stored, 201', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngestResult result = await ingest(repo).accept(body(report()));

      expect(result.status, 201);
      expect(repo.stored.single.message, 'boom');
    });

    test('the same report again is delivered and not stored twice', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngest endpoint = ingest(repo);
      await endpoint.accept(body(report()));

      final DVCrashIngestResult again = await endpoint.accept(body(report()));

      expect(again.status, 200);
      expect(repo.stored, hasLength(1));
    });

    test('not JSON is 400, and nothing repeats the body', () async {
      final DVCrashIngestResult result = await ingest(
        DVMemoryCrashReportRepository(),
      ).accept(utf8.encode('{"message": "$secret"'));

      expect(result.status, 400);
      expect(jsonEncode(result.toJson()), isNot(contains(secret)));
      expect(logged.join('\n'), isNot(contains(secret)));
    });

    test('JSON that is not a report is 400', () async {
      final DVCrashIngestResult result = await ingest(
        DVMemoryCrashReportRepository(),
      ).accept(utf8.encode(jsonEncode(<String, Object?>{'v': 1, 'message': secret})));

      expect(result.status, 400);
      expect(jsonEncode(result.toJson()), isNot(contains(secret)));
    });

    test('an install id or report id that is empty or absurd is 400', () async {
      final DVCrashIngest endpoint = ingest(DVMemoryCrashReportRepository());
      expect((await endpoint.accept(body(report(installId: '')))).status, 400);
      expect(
        (await endpoint.accept(body(report(installId: 'x' * 500)))).status,
        400,
      );
      expect((await endpoint.accept(body(report(id: '')))).status, 400);
    });

    test('over the size limit is 413 and never parsed', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngestResult result = await ingest(repo, maxBytes: 64)
          .accept(body(report(message: 'x' * 200)));

      expect(result.status, 413);
      expect(repo.stored, isEmpty);
    });
  });

  group('rate limits per install', () {
    test('past the budget an install is counted, not stored, and another '
        'install is not affected', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngest endpoint = ingest(repo, perInstallPerHour: 2);

      expect((await endpoint.accept(body(report(id: 'a')))).status, 201);
      expect((await endpoint.accept(body(report(id: 'b')))).status, 201);
      final DVCrashIngestResult limited =
          await endpoint.accept(body(report(id: 'c')));
      expect(limited.status, 202);
      expect(limited.outcome, DVCrashIngestOutcome.limited);
      expect(endpoint.limited('install-1'), 1);
      expect(
        (await endpoint.accept(body(report(id: 'd', installId: 'install-2'))))
            .status,
        201,
      );
      expect(repo.stored.map((DVCrashReport r) => r.id), <String>['a', 'b', 'd']);
    });

    test('the budget is per hour and comes back', () async {
      final DVCrashIngest endpoint =
          ingest(DVMemoryCrashReportRepository(), perInstallPerHour: 1);
      await endpoint.accept(body(report(id: 'a')));
      expect((await endpoint.accept(body(report(id: 'b')))).status, 202);

      now = now.add(const Duration(minutes: 61));

      expect((await endpoint.accept(body(report(id: 'c')))).status, 201);
    });

    test('a duplicate does not spend the budget', () async {
      final DVCrashIngest endpoint =
          ingest(DVMemoryCrashReportRepository(), perInstallPerHour: 1);
      await endpoint.accept(body(report(id: 'a')));
      expect((await endpoint.accept(body(report(id: 'a')))).status, 200);
    });
  });

  group('a store that fails', () {
    test('503, and neither the report nor the error is logged or answered',
        () async {
      final DVCrashIngestResult result = await ingest(_FailingRepository())
          .accept(body(report(message: 'charge failed for $secret')));

      expect(result.status, 503);
      expect(logged, isNotEmpty);
      expect(logged.join('\n'), isNot(contains(secret)));
      expect(jsonEncode(result.toJson()), isNot(contains(secret)));
    });

    test('a failed store does not spend the budget, so the retry lands',
        () async {
      final _FailingRepository repo = _FailingRepository();
      final DVCrashIngest endpoint = ingest(repo, perInstallPerHour: 1);
      expect((await endpoint.accept(body(report()))).status, 503);

      repo.failing = false;

      expect((await endpoint.accept(body(report()))).status, 201);
    });
  });

  group('the database repository', () {
    test('keeps the report and knows a duplicate by id', () async {
      final MemoryDVDatabaseAdapter database = MemoryDVDatabaseAdapter();
      final DVDatabaseCrashReportRepository repo =
          DVDatabaseCrashReportRepository(database);

      expect(await repo.put(report(), receivedAt: now), isTrue);
      expect(await repo.put(report(), receivedAt: now), isFalse);

      final List<Map<String, Object?>> rows = await database
          .query('SELECT * FROM ${DVDatabaseCrashReportRepository.table}');
      expect(rows, hasLength(1));
      expect(rows.single['install_id'], 'install-1');
      final DVCrashReport kept = DVCrashReport.fromJson(
        jsonDecode('${rows.single['report']}') as Map<String, Object?>,
      );
      expect(kept.message, 'boom');
    });
  });

  group('DVCrashSink.dartvel', () {
    late HttpServer server;
    late int status;
    late List<Map<String, Object?>> received;
    late Future<void> Function(HttpRequest request)? handle;

    setUp(() async {
      status = 201;
      received = <Map<String, Object?>>[];
      handle = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) async {
        if (handle != null) return handle!(request);
        received.add(
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>,
        );
        request.response.statusCode = status;
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    DVCrashSink sink() => DVCrashSink.dartvel(
          endpoint: () =>
              Uri.parse('http://127.0.0.1:${server.port}/api/_dartvel/crashes'),
          log: logged.add,
        );

    test('2xx is delivered', () async {
      await sink().send(report());
      expect(received.single['id'], 'r1');
    });

    test('a refusal is final: not thrown, so it is not retried forever',
        () async {
      for (final int refusal in <int>[400, 413]) {
        status = refusal;
        await expectLater(sink().send(report()), completes);
      }
      expect(logged.join('\n'), isNot(contains('boom')));
    });

    test('a server error is thrown, so the record stays for next launch',
        () async {
      status = 503;
      await expectLater(sink().send(report()), throwsA(anything));
    });

    test('a source past its budget is thrown, so the record is sent again '
        'later rather than lost', () async {
      // The per-source refusal is 429 so that installs behind a busy address
      // are delayed, not dropped. A sink that treated it as final would drop
      // them.
      status = 429;
      await expectLater(sink().send(report()), throwsA(anything));
    });

    test('nothing listening is thrown', () async {
      final int port = server.port;
      await server.close(force: true);
      final DVCrashSink dead = DVCrashSink.dartvel(
        endpoint: () => Uri.parse('http://127.0.0.1:$port/api/_dartvel/crashes'),
      );
      await expectLater(dead.send(report()), throwsA(anything));
    });

    test('recoverAndSend through the sink into a backend ingest', () async {
      final DVMemoryCrashReportRepository repo = DVMemoryCrashReportRepository();
      final DVCrashIngest backend = ingest(repo);
      handle = (HttpRequest request) async {
        final List<int> bytes = await request
            .fold<List<int>>(<int>[], (List<int> a, List<int> b) => a..addAll(b));
        final DVCrashIngestResult result = await backend.accept(bytes);
        request.response.statusCode = result.status;
        await request.response.close();
      };
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      DVCrashReporting(
        store: store,
        context: () =>
            const DVCrashContext(release: '1.0.0', installId: 'install-1'),
        onDiagnostic: (String code, String message) {},
      ).record(StateError('last run'), StackTrace.current, fatal: true);

      final int sent = await DVCrashReporting(
        store: store,
        sink: sink(),
        context: () =>
            const DVCrashContext(release: '1.0.0', installId: 'install-1'),
        onDiagnostic: (String code, String message) {},
      ).recoverAndSend();

      expect(sent, 1);
      expect(repo.stored.single.message, 'Bad state: last run');
      expect(store.raw, isEmpty);
    });
  });
}
