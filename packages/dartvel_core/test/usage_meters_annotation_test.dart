// @DVMeter: a meter declared once, in Dart, and read through a generated
// member, so a misspelt meter name is a compile error rather than a second
// meter nobody bills.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

abstract class _Meters {
  @DVMeter(
    unit: 'call',
    limit: DVLimit.entitlement,
    atLimit: DVQuota.block,
    notifyAt: <double>[0.8, 1.0],
  )
  static const DVMeterKind apiCalls = DVMeter.counter;

  @DVMeter(unit: 'GB-month', gaugeBilling: DVGaugeBilling.peak)
  static const DVMeterKind storedBytes = DVMeter.gauge;
}

void main() {
  test('the declaration is a const annotation over a meter kind', () {
    expect(_Meters.apiCalls, DVMeterKind.counter);
    expect(_Meters.storedBytes, DVMeterKind.gauge);
  });

  test('a declaration becomes the definition it describes', () {
    final DVMeterDefinition calls = const DVMeter(
      unit: 'call',
      limit: DVLimit.entitlement,
      atLimit: DVQuota.block,
      notifyAt: <double>[0.8, 1.0],
      grace: Duration(hours: 6),
    ).definition('apiCalls', kind: DVMeter.counter);
    expect(calls.name, 'apiCalls');
    expect(calls.unit, 'call');
    expect(calls.kind, DVMeterKind.counter);
    expect(calls.limit, DVLimit.entitlement);
    expect(calls.atLimit, DVQuota.block);
    expect(calls.notifyAt, <double>[0.8, 1.0]);
    expect(calls.grace, const Duration(hours: 6));

    final DVMeterDefinition stored =
        const DVMeter(unit: 'GB-month', gaugeBilling: DVGaugeBilling.peak)
            .definition('storedBytes', kind: DVMeter.gauge);
    expect(stored.kind, DVMeterKind.gauge);
    expect(stored.gaugeBilling, DVGaugeBilling.peak);
  });

  test('a limit with no behaviour at it is still DV-METER-005', () {
    expect(
      () => const DVMeter(unit: 'call', limit: DVLimit.fixed(10))
          .definition('apiCalls', kind: DVMeter.counter),
      throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}', 'message', contains('DV-METER-005'))),
    );
  });
}
