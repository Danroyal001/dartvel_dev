// dartvel.crashes as the installation applies it.
//
// A setting that parses and then is not handed to the reporter is the same
// silent failure as one that does not parse: the pubspec says 0.25 and every
// non-fatal is kept, says one full report and a crash loop fills the disk, or
// says crash reporting is off for debug builds and the hooks go in anyway.
import 'dart:io';
import 'dart:ui';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FlutterExceptionHandler? testHandler;
  late ErrorCallback? dispatcherBefore;
  late List<String> codes;

  setUp(() {
    testHandler = FlutterError.onError;
    dispatcherBefore = PlatformDispatcher.instance.onError;
    FlutterError.onError = (FlutterErrorDetails d) {};
    codes = <String>[];
  });

  tearDown(() {
    const DVCrashes().installation?.uninstall();
    FlutterError.onError = testHandler;
    PlatformDispatcher.instance.onError = dispatcherBefore;
  });

  DVCrashInstallation? installWith(
    DVCrashConfig config,
    DVMemoryCrashStore store,
  ) =>
      const DVCrashes().installApplication(
        appId: 'crash_config_install_test',
        release: '1.0.0',
        store: store,
        installId: 'install-1',
        config: config,
        onDiagnostic: (String code, String message) => codes.add(code),
        evenUnderTest: true,
      );

  FlutterErrorDetails details(String message) => FlutterErrorDetails(
        exception: StateError(message),
        stack: StackTrace.current,
      );

  test('installation that fails does not take the application down with it',
      () {
    // The generated runtime installs crash reporting from the router's
    // constructor, before the first frame. An exception here is an
    // application that never draws -- on the web the site build said only
    // "Captured 0 of N routes" -- so a failure is taken back and reported,
    // never thrown.
    final FlutterExceptionHandler? before = FlutterError.onError;
    final ErrorCallback? dispatcher = PlatformDispatcher.instance.onError;

    DVCrashInstallation? installation;
    expect(
      () => installation = const DVCrashes().installApplication(
        appId: 'crash_config_install_test',
        release: '1.0.0',
        store: DVMemoryCrashStore(),
        installId: 'install-1',
        onDiagnostic: (String code, String message) =>
            throw StateError('diagnostics sink is down'),
        evenUnderTest: true,
      ),
      returnsNormally,
    );

    expect(installation, isNull);
    expect(const DVCrashes().installation, isNull);
    expect(FlutterError.onError, same(before));
    expect(PlatformDispatcher.instance.onError, same(dispatcher));
  });

  test('disabled for this build: no hooks go in, and the build says so', () {
    // flutter test runs a debug build.
    final FlutterExceptionHandler? before = FlutterError.onError;
    final DVMemoryCrashStore store = DVMemoryCrashStore();

    final DVCrashInstallation? installation = installWith(
      const DVCrashConfig(disabledIn: <DVCrashBuildMode>{DVCrashBuildMode.debug}),
      store,
    );

    expect(installation, isNull);
    expect(FlutterError.onError, same(before));
    expect(codes, <String>['DV-CRASH-009']);
    FlutterError.reportError(details('ignored'));
    expect(store.raw, isEmpty);
  });

  test('disabled only for release: a debug build installs', () {
    expect(
      installWith(
        const DVCrashConfig(
            disabledIn: <DVCrashBuildMode>{DVCrashBuildMode.release}),
        DVMemoryCrashStore(),
      ),
      isNotNull,
    );
    expect(codes, isNot(contains('DV-CRASH-009')));
  });

  test('the sample rate reaches the reporter', () {
    final DVMemoryCrashStore store = DVMemoryCrashStore();
    installWith(const DVCrashConfig(nonFatalSampleRate: 0), store);

    expect(const DVCrashes().record(StateError('caught')), isNull);
    expect(codes, contains('DV-CRASH-008'));
    // A crash is never sampled.
    FlutterError.reportError(details('crash'));
    expect(store.raw, hasLength(1));
  });

  test('the per-release limit reaches the reporter', () {
    final DVMemoryCrashStore store = DVMemoryCrashStore();
    installWith(const DVCrashConfig(fullReportsPerRelease: 1), store);

    FlutterError.reportError(details('first'));
    FlutterError.reportError(details('second'));

    expect(store.raw, hasLength(1));
    expect(codes, contains('DV-CRASH-004'));
  });

  test('the breadcrumb size reaches the reporter', () {
    final DVCrashInstallation installation = installWith(
      const DVCrashConfig(breadcrumbs: 2),
      DVMemoryCrashStore(),
    )!;

    expect(installation.reporter.breadcrumbs.capacity, 2);
  });

  group('sink: dartvel', () {
    test("sends the previous run's reports to the backend the runtime names",
        () async {
      final HttpServer server =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final List<String> paths = <String>[];
      server.listen((HttpRequest request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        request.response.statusCode = 201;
        await request.response.close();
      });
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      DVCrashReporting(
        store: store,
        context: () =>
            const DVCrashContext(release: '1.0.0', installId: 'install-1'),
        onDiagnostic: (String code, String message) {},
      ).record(StateError('last run'), StackTrace.current, fatal: true);

      final DVCrashInstallation installation =
          const DVCrashes().installApplication(
        appId: 'crash_config_install_test',
        release: '1.0.0',
        store: store,
        installId: 'install-1',
        config: const DVCrashConfig(sink: DVCrashSinkChoice.dartvel),
        api: (String path) =>
            Uri.parse('http://127.0.0.1:${server.port}/api$path'),
        onDiagnostic: (String code, String message) => codes.add(code),
        evenUnderTest: true,
      )!;

      expect(await installation.recovered, 1);
      expect(paths, <String>['/api/_dartvel/crashes']);
      expect(store.raw, isEmpty);
    });

    test('with no API to reach it is refused, not sent nowhere', () {
      expect(
        () => installWith(
          const DVCrashConfig(sink: DVCrashSinkChoice.dartvel),
          DVMemoryCrashStore(),
        ),
        throwsArgumentError,
      );
    });

    test('sink: none sends nothing and keeps the record', () async {
      final DVMemoryCrashStore store = DVMemoryCrashStore();
      DVCrashReporting(
        store: store,
        context: () =>
            const DVCrashContext(release: '1.0.0', installId: 'install-1'),
        onDiagnostic: (String code, String message) {},
      ).record(StateError('last run'), StackTrace.current, fatal: true);

      final DVCrashInstallation installation =
          installWith(const DVCrashConfig(), store)!;

      expect(await installation.recovered, 0);
      expect(store.raw, hasLength(1));
    });
  });

  test('the identity category comes from the configuration', () async {
    const DVConsentCategory category = DVConsentCategory('crash_identity');
    final DVConsent consent = DVConsent(
      policy: DVConsentPolicy(
        version: '1',
        categories: const <DVConsentDeclaration>[
          DVConsentDeclaration(category),
        ],
      ),
      database: MemoryDVDatabaseAdapter(),
      installId: 'install-1',
      onDiagnostic: (String code, String message) {},
    );
    await consent.ensureSchema();
    await consent.record(<DVConsentCategory, bool>{category: true});
    final DVMemoryCrashStore store = DVMemoryCrashStore();
    installWith(const DVCrashConfig(identityConsent: category), store);

    const DVCrashes().identify('user-42', consent: consent);
    FlutterError.reportError(details('boom'));

    expect(store.pending().single.report!.context.userId, 'user-42');
  });
}
