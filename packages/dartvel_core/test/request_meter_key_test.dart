// A backend request records usage under its own key, with nothing added.
//
// Without it a handler that records a meter has to invent a key, and the
// obvious invention -- a fresh id per call -- makes every retry new, which
// is the overcharge the key exists to prevent. With it, a client retry that
// repeats its Idempotency-Key counts once, and two different requests are
// two records.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVMeters meters;
  final DVMeterDefinition calls = DVMeterDefinition('api_calls', unit: 'call');

  setUp(() {
    meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
    );
  });

  tearDown(DVTenants.reset);

  Map<String, Object?> request({String? key, String path = '/charge'}) =>
      <String, Object?>{
        'method': 'POST',
        'path': path,
        'headers': <String, String>{if (key != null) 'Idempotency-Key': key},
      };

  Future<void> serve(Map<String, Object?> req) => dvWithRequestMeterKey(
      req, () async => meters.record(calls, 1));


  test('a request with no key of its own still records', () async {
    await serve(request());
    expect(await meters.usage(calls, tenant: DVTenants.defaultTenant), 1);
  });

  test('two requests are two records', () async {
    await serve(request());
    await serve(request());
    expect(await meters.usage(calls, tenant: DVTenants.defaultTenant), 2);
  });

  test("a client retry under the same Idempotency-Key counts once", () async {
    await serve(request(key: 'charge-41'));
    await serve(request(key: 'charge-41'));
    expect(await meters.usage(calls, tenant: DVTenants.defaultTenant), 1);
  });

  test('the same Idempotency-Key on another endpoint is another operation',
      () async {
    await serve(request(key: 'k-1', path: '/charge'));
    await serve(request(key: 'k-1', path: '/refund'));
    expect(await meters.usage(calls, tenant: DVTenants.defaultTenant), 2);
  });

  test('the key is in scope for the whole handler', () async {
    String? seen;
    await dvWithRequestMeterKey(request(key: 'abc'), () async {
      await Future<void>.delayed(Duration.zero);
      seen = DVMeters.currentIdempotencyKey;
    });
    expect(seen, isNotNull);
    expect(seen, contains('abc'));
  });
}
