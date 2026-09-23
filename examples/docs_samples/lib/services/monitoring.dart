import '../dartvel_client/dartvel_client.dart';

// docs:start monitoring-log
// One line, with whatever belongs beside it. DV.log and
// DV.ObservabilityAndLogging are the surface; there is no second logger to
// configure per package.
void recordRefund(String orderId, int cents) {
  DV.log(
    'refunded an order',
    context: <String, Object>{'order': orderId, 'cents': cents},
  );
}
// docs:end

// docs:start monitoring-trace
// Timed as one named step, so a slow checkout points at the work inside
// it instead of at the request as a whole.
Future<T> priced<T>(Future<T> Function() work) =>
    DV.ObservabilityAndLogging.trace<T>('pricing', work);
// docs:end

// docs:start monitoring-slo
// A promise with a budget attached, and a rule that fires on the budget
// instead of on a single bad minute.
const DVServiceLevel checkout = DVServiceLevel(
  name: 'checkout',
  objective: DVObjective.successRate(0.995, over: Duration(days: 30)),
  applies: DVAppliesTo.backendFunction('placeOrder'),
);

final DVAlertRule backlog = DVAlertRule(
  name: 'mail-backlog',
  signal: const DVSignalRef.queueDepth('mail'),
  condition: const DVAlertWhen.above(100),
  // A rule that fires on the first sample pages somebody for a spike that
  // cleared itself.
  forDuration: const Duration(minutes: 5),
  notify: const <DVAlertTarget>[DVAlertTarget.team('ops')],
);
// docs:end
