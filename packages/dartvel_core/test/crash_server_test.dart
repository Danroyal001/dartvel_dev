// Crash reporting in a server process: the generated backend's unhandled
// errors, recorded through the same runtime with the role of the process
// that had them.
//
// A server is not a phone. It does not restart to send, so a report kept
// for "the next launch" is a report nobody sees until the next deploy; and
// three processes run one binary, so a report that does not say which role
// crashed sends an operator to the web logs for a cron failure. The silent
// failures:
//
//  * an unhandled request error sampled away as though it were a caught one;
//  * the recorder throwing inside the request's error path, or recursing,
//    and turning a 500 into a dropped connection;
//  * a report recorded and never sent while the process stays up;
//  * a failed schedule kept in a list nothing reads;
//  * records written to `/` by a process whose working directory is root.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _ThrowingStore extends DVMemoryCrashStore {
  int writes = 0;

  @override
  void writeSync(DVCrashReport report) {
    writes++;
    DVServerCrashes.record(StateError('inside the recorder'), StackTrace.current);
    throw StateError('disk full');
  }
}

void main() {
  late List<String> codes;

  setUp(() {
    codes = <String>[];
    DVServerCrashes.resetForTest();
  });
  tearDown(DVServerCrashes.resetForTest);

  DVCrashReporting? install({
    DVProcessRole role = DVProcessRole.web,
    DVCrashConfig config = const DVCrashConfig(),
    DVCrashStore? store,
    DVCrashSink? sink,
  }) =>
      DVServerCrashes.install(
        appId: 'shop',
        release: '1.4.0',
        role: role,
        config: config,
        store: store ?? DVMemoryCrashStore(),
        sink: sink,
        installId: 'server-1',
        onDiagnostic: (String code, String message) => codes.add(code),
      );

  group('recording', () {
    for (final DVProcessRole role in DVProcessRole.values) {
      test('an unhandled error in a ${role.name} process says ${role.name}',
          () {
        final DVMemoryCrashStore store = DVMemoryCrashStore();
        install(role: role, store: store);

        DVServerCrashes.record(StateError('boom'), StackTrace.current);

        final DVCrashReport report = store.pending().single.report!;
        expect(report.context.role, role.name);
        expect(report.context.deviceClass, 'server');
        expect(report.context.release, '1.4.0');
        expect(report.kind, DVCrashKind.fatal);
      });
    }

    test('an unhandled error is never sampled away', () {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      install(
        store: store,
        config: const DVCrashConfig(nonFatalSampleRate: 0),
      );

      DVServerCrashes.record(StateError('boom'), StackTrace.current);

      expect(store.raw, hasLength(1));
    });

    test('the role survives the round trip and is absent when unset', () {
      const DVCrashContext withRole =
          DVCrashContext(release: '1', installId: 'i', role: 'cron');
      expect(DVCrashContext.fromJson(withRole.toJson()).role, 'cron');
      expect(
        const DVCrashContext(release: '1', installId: 'i').toJson(),
        isNot(contains('role')),
      );
    });

    test('before installation nothing is recorded and nothing throws', () {
      expect(
        DVServerCrashes.record(StateError('early'), StackTrace.current),
        isNull,
      );
    });

    test('a store that fails neither throws nor recurses', () {
      final _ThrowingStore store = _ThrowingStore();
      install(store: store);

      expect(
        () => DVServerCrashes.record(StateError('boom'), StackTrace.current),
        returnsNormally,
      );
      expect(store.writes, 1);
      expect(DVServerCrashes.lastFailure, isA<StateError>());
    });

    test('disabled for this build: nothing installed, and it is said', () {
      expect(
        install(
          config: const DVCrashConfig(
            disabledIn: <DVCrashBuildMode>{
              DVCrashBuildMode.debug,
              DVCrashBuildMode.profile,
              DVCrashBuildMode.release,
            },
          ),
        ),
        isNull,
      );
      expect(codes, <String>['DV-CRASH-009']);
      expect(
        DVServerCrashes.record(StateError('boom'), StackTrace.current),
        isNull,
      );
    });
  });

  group('sending', () {
    test('a report is sent while the process stays up', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      final DVMemoryCrashSink sink = DVMemoryCrashSink();
      install(store: store, sink: sink);
      await DVServerCrashes.idle;

      DVServerCrashes.record(StateError('boom'), StackTrace.current);
      await DVServerCrashes.idle;

      expect(sink.received.single.message, 'Bad state: boom');
      expect(store.raw, isEmpty);
    });

    test('what the previous process left is sent at install', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      DVCrashReporting(
        store: store,
        context: () =>
            const DVCrashContext(release: '1.4.0', installId: 'server-1'),
        onDiagnostic: (String code, String message) {},
      ).record(StateError('last process'), StackTrace.current, fatal: true);
      final DVMemoryCrashSink sink = DVMemoryCrashSink();

      install(store: store, sink: sink);
      await DVServerCrashes.idle;

      expect(sink.received.single.message, 'Bad state: last process');
    });

    test('a failed send keeps the record', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      install(store: store, sink: DVMemoryCrashSink(failing: true));

      DVServerCrashes.record(StateError('boom'), StackTrace.current);
      await DVServerCrashes.idle;

      expect(store.raw, hasLength(1));
    });
  });

  group('the repository sink', () {
    test("stores a server's own report without going over HTTP", () async {
      final DVMemoryCrashReportRepository repository =
          DVMemoryCrashReportRepository();
      await DVCrashSink.repository(repository).send(
        DVCrashReport(
          id: 'r1',
          kind: DVCrashKind.fatal,
          errorType: 'StateError',
          message: 'boom',
          frames: const <DVCrashFrame>[],
          fingerprint: 'f',
          context: const DVCrashContext(release: '1', installId: 'i'),
          occurredAt: DateTime.utc(2026, 9, 14),
        ),
      );
      expect(repository.stored.single.id, 'r1');
    });
  });

  group('where a server keeps its records', () {
    test('DARTVEL_CRASH_DIR wins', () {
      expect(
        dvServerCrashDirectoryFor(
          appId: 'shop',
          environment: const <String, String>{'DARTVEL_CRASH_DIR': '/var/crashes'},
          currentDirectory: '/srv/shop',
          tempDirectory: '/tmp',
        ),
        '/var/crashes',
      );
    });

    test('beside the application, and never at the root', () {
      expect(
        dvServerCrashDirectoryFor(
          appId: 'shop',
          environment: const <String, String>{},
          currentDirectory: '/srv/shop',
          tempDirectory: '/tmp',
        ),
        '/srv/shop/.dartvel/crashes',
      );
      expect(
        dvServerCrashDirectoryFor(
          appId: 'shop',
          environment: const <String, String>{},
          currentDirectory: '/',
          tempDirectory: '/tmp',
        ),
        '/tmp/dartvel-crashes/shop',
      );
    });
  });

  group('a schedule that fails', () {
    test('is handed to onFailure, not only kept in a list', () async {
      final List<DVScheduledFailure> failures = <DVScheduledFailure>[];
      DateTime now = DateTime.utc(2026, 9, 14, 2, 59, 30);
      final DVScheduler scheduler = DVScheduler(
        clock: () => now,
        onFailure: failures.add,
      )..register(
          'nightly',
          '* * * * *',
          () async => throw StateError('schedule failed'),
        );
      await scheduler.tick();
      now = now.add(const Duration(minutes: 1));
      await scheduler.tick();

      expect(failures.single.name, 'nightly');
      expect(failures.single.error, isA<StateError>());
    });
  });
}
