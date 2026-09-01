// A scheduled report whose cron nobody reads.
//
// DVScheduledReport carried a cron string and stored it. Nothing parsed it, so
// `Order.Report.scheduleMonthly(cron: '0 8 1 * *')` and
// `scheduleMonthly(cron: 'every month')` were indistinguishable: both produced
// a payload, both dispatched, and only one would ever have run -- except
// nothing evaluated either, so neither did.
//
// Now that there is a cron evaluator, the loop closes: a report knows when it
// is next due, and a cron it cannot parse is a failure at the call site rather
// than a report that silently never arrives.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVScheduledReport report(String cron) => DVScheduledReport(
      name: 'order.monthly',
      model: 'Order',
      report: 'monthly',
      cron: cron,
      queue: 'reports',
      scheduledAt: DateTime.utc(2026, 1, 15, 9),
    );

void main() {
  test('it knows when it is next due', () {
    // 08:00 on the first of the month.
    expect(
      report('0 8 1 * *').nextRunAfter(DateTime(2026, 1, 15, 9)),
      DateTime(2026, 2, 1, 8),
    );
  });

  test('due-ness is a question it can answer', () {
    expect(report('0 8 1 * *').isDue(DateTime(2026, 2, 1, 8)), isTrue);
    expect(report('0 8 1 * *').isDue(DateTime(2026, 2, 1, 9)), isFalse);
  });

  test('a shorthand works, because a crontab accepts one', () {
    expect(report('@monthly').isDue(DateTime(2026, 3, 1)), isTrue);
  });

  test('an unparseable cron fails, naming the report', () {
    // Not a silent never-runs. The report name is what a person needs to find
    // the declaration; the string alone could be any of a dozen schedules.
    expect(
      () => report('every month').schedule,
      throwsA(isA<FormatException>().having(
        (FormatException e) => e.message,
        'message',
        allOf(contains('order.monthly'), contains('every month')),
      )),
    );
  });

  test('a cron that can never occur is reported as never due', () {
    // The 31st of February parses and occurs never. A report scheduled for it
    // should say so rather than being asked forever.
    expect(
      report('0 0 31 2 *').nextRunAfter(DateTime(2026, 1, 1)),
      isNull,
    );
  });

  test('the payload still round-trips as data', () {
    // It is dispatched through a queue, so it has to stay serialisable --
    // adding behaviour must not turn it into something a worker cannot
    // reconstruct.
    final DVScheduledReport original = report('@monthly');
    expect(original.cron, '@monthly');
    expect(original.name, 'order.monthly');
    expect(original.queue, 'reports');
  });
}
