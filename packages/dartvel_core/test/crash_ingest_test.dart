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
    int maxBytes = 65536,
  }) =>
      DVCrashIngest(
        repository: repository,
        perInstallPerHour: perInstallPerHour,
        maxBytes: maxBytes,
        clock: () => now,
        log: logged.add,
      );

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
