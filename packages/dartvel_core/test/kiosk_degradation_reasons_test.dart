// Two kiosk degradations no kiosk could ever report.
//
// DVKioskDegradation.routeBlocked (DV-KIOSK-006) and .lockedOut
// (DV-KIOSK-003) were declared, each with a registry entry describing what it
// meant, and neither was ever assigned. The conditions behind both are real
// and reached every day -- a kiosk redirecting a route outside routes.allow,
// and the lockout after maxAttempts wrong PINs -- so what was missing was the
// report, not the behaviour.
//
// The route gate blocked silently: dvKioskRouteRedirect sent /admin to the
// home route and said nothing, so a kiosk that quietly refused the page an
// operator asked for looked identical to one whose link was wrong. The
// lockout did report DV-KIOSK-003, as a string literal written beside the
// member that names it, which is the same defect from the other side: two
// places to change and one of them silently stale.
//
// A test that only asserted "it degraded" would pass before the fix, because
// a blocked route already redirected and a lockout already carried a code.
// Each assertion below names the member, and each has a control that must
// report nothing at all.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVKioskPolicy _policy({
  List<String> allow = const <String>[],
  String home = '/welcome',
  Map<String, Object?> exit = const <String, Object?>{},
}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'scope': 'device',
        'home': home,
        'routes': <String, Object?>{'allow': allow},
        'exit': exit,
      },
    });

List<DVLogRecord> _kioskRecords() => DVObservability.recentLogs
    .where((DVLogRecord r) => r.code?.startsWith('DV-KIOSK-') ?? false)
    .toList();

void main() {
  group('a blocked route says so', () {
    setUp(() {
      // At debug, because that is the level the registry gives DV-KIOSK-006
      // and the default logger keeps `info` and above. A kiosk refusing the
      // routes it was told to refuse is ordinary traffic through this gate;
      // an application that wants to watch it lowers the level, exactly as
      // here.
      DVObservability.useLogging(
        sinks: const <DVLogSink>[],
        level: DVLogLevel.debug,
      );
      dvApplyKioskContainment(
        _policy(allow: <String>['/welcome', '/order/**']),
      );
    });
    tearDown(() {
      dvResetKioskContainment();
      DVObservability.resetLogging();
    });

    test('a route outside routes.allow reports routeBlocked', () {
      final String? redirect = dvKioskRouteRedirect('/admin');

      expect(redirect, '/welcome', reason: 'it still redirects');
      final List<DVLogRecord> records = _kioskRecords();
      expect(records, hasLength(1));
      expect(records.single.code, DVKioskDegradation.routeBlocked.code);
      expect(records.single.code, 'DV-KIOSK-006');
    });

    test('the blocked route is named, so the report can be acted on', () {
      dvKioskRouteRedirect('/admin/users');

      final DVLogRecord record = _kioskRecords().single;
      expect(record.context['route'], '/admin/users');
      expect(record.context['home'], '/welcome');
    });

    test('an allowed route reports nothing', () {
      // The control. Every navigation goes through this gate, so a report on
      // an allowed route would fill a kiosk's log with its own ordinary use.
      expect(dvKioskRouteRedirect('/order/5'), isNull);
      expect(_kioskRecords(), isEmpty);
    });

    test('the home route reports nothing, even outside the list', () {
      // It is never redirected -- home redirecting to home is a loop -- so
      // there is nothing blocked to report.
      expect(dvKioskRouteRedirect('/welcome'), isNull);
      expect(_kioskRecords(), isEmpty);
    });

    test('with no kiosk holding, nothing is blocked and nothing is said', () {
      dvResetKioskContainment();

      expect(dvKioskRouteRedirect('/admin'), isNull);
      expect(_kioskRecords(), isEmpty);
    });

    test('DV-KIOSK-006 is debug: an ordinary kiosk refusing a page', () {
      expect(DVDiagnostics.find('DV-KIOSK-006')!.level, 'debug');
    });

    test('so the default logger keeps it out of an ordinary run', () {
      // Stated rather than discovered: at the default level a blocked route
      // is not in the log, and somebody looking for it has to ask for debug.
      // The record is made either way -- the counter behind the logger sees
      // every one -- which is what keeps that choice from hiding a problem.
      DVObservability.resetLogging();

      expect(dvKioskRouteRedirect('/admin'), '/welcome');
      expect(_kioskRecords(), isEmpty);
    });
  });

  group('a lockout carries the member that names it', () {
    DVKioskRuntime runtimeWith({int maxAttempts = 2}) => DVKioskRuntime(
          _policy(exit: <String, Object?>{
            'method': 'pin',
            'pin': 'secret:PIN',
            'maxAttempts': maxAttempts,
            'lockoutFor': '10m',
          }),
          readSecret: (String name) async => name == 'PIN' ? '4821' : null,
        );

    test('the attempt that hits maxAttempts reports lockedOut', () async {
      final DVKioskRuntime runtime = runtimeWith();
      await runtime.resume();

      await runtime.exit(const DVKioskExitRequest.pin('0000'));
      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('0000'));

      expect(result.granted, isFalse);
      expect(result.degradation, DVKioskDegradation.lockedOut);
      expect(result.code, 'DV-KIOSK-003');
      runtime.stop();
    });

    test('an attempt during the lockout reports it too', () async {
      final DVKioskRuntime runtime = runtimeWith();
      await runtime.resume();
      await runtime.exit(const DVKioskExitRequest.pin('0000'));
      await runtime.exit(const DVKioskExitRequest.pin('0000'));

      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isFalse,
          reason: 'the right PIN during a lockout is still refused');
      expect(result.degradation, DVKioskDegradation.lockedOut);
      runtime.stop();
    });

    test('a wrong attempt below the limit degrades nothing', () async {
      // The control: this one already returned granted: false with no code,
      // so an assertion on "not granted" alone proves nothing about the
      // member.
      final DVKioskRuntime runtime = runtimeWith(maxAttempts: 3);
      await runtime.resume();

      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('0000'));

      expect(result.granted, isFalse);
      expect(result.degradation, DVKioskDegradation.none);
      expect(result.code, isNull);
      runtime.stop();
    });

    test('a granted exit degrades nothing', () async {
      final DVKioskRuntime runtime = runtimeWith();
      await runtime.resume();

      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.granted, isTrue);
      expect(result.degradation, DVKioskDegradation.none);
      runtime.stop();
    });

    test('no policy reports noPolicy, from the member rather than a literal',
        () async {
      final DVKioskRuntime runtime =
          DVKioskRuntime(DVKioskPolicy.parse(null));

      final DVKioskExitResult result =
          await runtime.exit(const DVKioskExitRequest.pin('4821'));

      expect(result.degradation, DVKioskDegradation.noPolicy);
      expect(result.code, 'DV-KIOSK-005');
    });
  });

  group('the enum and the registry agree', () {
    test('every degradation but none has a code', () {
      for (final DVKioskDegradation d in DVKioskDegradation.values) {
        expect(d.code, d == DVKioskDegradation.none ? isNull : isNotNull,
            reason: '$d');
      }
    });

    test('every code a member names is registered and explainable', () {
      // A member whose code is absent from the registry is a degradation
      // `dartvel explain` cannot describe, which is how DV-KIOSK-006 became
      // documentation for something no kiosk could produce.
      for (final DVKioskDegradation d in DVKioskDegradation.values) {
        final String? code = d.code;
        if (code == null) continue;
        expect(DVDiagnostics.find(code), isNotNull, reason: '$d -> $code');
      }
    });

    test('no two members share a code', () {
      final List<String> codes = <String>[
        for (final DVKioskDegradation d in DVKioskDegradation.values)
          if (d.code != null) d.code!,
      ];
      expect(codes.toSet(), hasLength(codes.length));
    });
  });
}
