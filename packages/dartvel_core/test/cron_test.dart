// Cron expressions, and the parts of them that are usually wrong.
//
// @DVBackendCron and @DVClientCron were collected into generated metadata and
// nothing ever evaluated one: there was no cron parser in the framework at
// all, so a schedule was a string that travelled from an annotation into a
// generated list and stopped there.
//
// The tests below concentrate on the rules people get wrong rather than on
// "*/5 works". Chief among them is the day-of-month/day-of-week rule, which
// is an OR when both are restricted and an AND in most naive implementations
// -- a job written to run on the 1st and on Mondays then runs only when the
// 1st is a Monday, which is roughly once a year and looks like the scheduler
// being broken rather than the expression being misread.
import 'package:dartvel_core/src/scheduling/cron.dart';
import 'package:test/test.dart';

DateTime at(int y, int mo, int d, int h, int mi) => DateTime(y, mo, d, h, mi);

void main() {
  group('parsing', () {
    test('every minute', () {
      final DVCronSchedule s = DVCronSchedule.parse('* * * * *');
      expect(s.matches(at(2026, 1, 1, 0, 0)), isTrue);
      expect(s.matches(at(2026, 7, 9, 13, 37)), isTrue);
    });

    test('a fixed time', () {
      final DVCronSchedule s = DVCronSchedule.parse('30 2 * * *');
      expect(s.matches(at(2026, 3, 4, 2, 30)), isTrue);
      expect(s.matches(at(2026, 3, 4, 2, 31)), isFalse);
      expect(s.matches(at(2026, 3, 4, 3, 30)), isFalse);
    });

    test('a step', () {
      final DVCronSchedule s = DVCronSchedule.parse('*/15 * * * *');
      for (final int minute in <int>[0, 15, 30, 45]) {
        expect(s.matches(at(2026, 1, 1, 9, minute)), isTrue);
      }
      expect(s.matches(at(2026, 1, 1, 9, 7)), isFalse);
    });

    test('a range', () {
      final DVCronSchedule s = DVCronSchedule.parse('0 9-17 * * *');
      expect(s.matches(at(2026, 1, 1, 9, 0)), isTrue);
      expect(s.matches(at(2026, 1, 1, 17, 0)), isTrue);
      expect(s.matches(at(2026, 1, 1, 18, 0)), isFalse);
    });

    test('a stepped range', () {
      final DVCronSchedule s = DVCronSchedule.parse('0 9-17/4 * * *');
      expect(s.matches(at(2026, 1, 1, 9, 0)), isTrue);
      expect(s.matches(at(2026, 1, 1, 13, 0)), isTrue);
      expect(s.matches(at(2026, 1, 1, 17, 0)), isTrue);
      expect(s.matches(at(2026, 1, 1, 11, 0)), isFalse);
    });

    test('a list', () {
      final DVCronSchedule s = DVCronSchedule.parse('0 0 1,15 * *');
      expect(s.matches(at(2026, 4, 1, 0, 0)), isTrue);
      expect(s.matches(at(2026, 4, 15, 0, 0)), isTrue);
      expect(s.matches(at(2026, 4, 7, 0, 0)), isFalse);
    });

    test('sunday is both 0 and 7', () {
      // Both spellings are in use, and a scheduler that knows only one skips
      // every Sunday job written the other way.
      final DateTime sunday = at(2026, 3, 1, 0, 0);
      expect(sunday.weekday, DateTime.sunday);
      expect(DVCronSchedule.parse('0 0 * * 0').matches(sunday), isTrue);
      expect(DVCronSchedule.parse('0 0 * * 7').matches(sunday), isTrue);
    });

    test('names are accepted for months and weekdays', () {
      expect(DVCronSchedule.parse('0 0 * JAN MON').matches(at(2026, 1, 5, 0, 0)),
          isTrue);
      expect(DVCronSchedule.parse('0 0 * jan mon').matches(at(2026, 1, 5, 0, 0)),
          isTrue);
    });

    test('the shorthands', () {
      expect(DVCronSchedule.parse('@daily').matches(at(2026, 5, 5, 0, 0)),
          isTrue);
      expect(DVCronSchedule.parse('@daily').matches(at(2026, 5, 5, 0, 1)),
          isFalse);
      expect(DVCronSchedule.parse('@hourly').matches(at(2026, 5, 5, 13, 0)),
          isTrue);
      expect(DVCronSchedule.parse('@monthly').matches(at(2026, 5, 1, 0, 0)),
          isTrue);
    });
  });

  group('the day-of-month and day-of-week rule', () {
    test('when both are restricted, either one matches', () {
      // The rule people get wrong. `0 0 1 * MON` means the 1st OR a Monday,
      // not the 1st AND a Monday -- which would be about once a year.
      final DVCronSchedule s = DVCronSchedule.parse('0 0 1 * MON');

      // The 1st of April 2026 is a Wednesday.
      expect(at(2026, 4, 1, 0, 0).weekday, DateTime.wednesday);
      expect(s.matches(at(2026, 4, 1, 0, 0)), isTrue, reason: 'the 1st');

      // A Monday that is not the 1st.
      expect(at(2026, 4, 6, 0, 0).weekday, DateTime.monday);
      expect(s.matches(at(2026, 4, 6, 0, 0)), isTrue, reason: 'a Monday');

      expect(s.matches(at(2026, 4, 7, 0, 0)), isFalse);
    });

    test('when only one is restricted it is an ordinary AND', () {
      // `0 0 1 * *` is the 1st, and must not match every day because the
      // weekday field is unrestricted.
      final DVCronSchedule s = DVCronSchedule.parse('0 0 1 * *');
      expect(s.matches(at(2026, 4, 1, 0, 0)), isTrue);
      expect(s.matches(at(2026, 4, 6, 0, 0)), isFalse);
    });

    test('weekday alone still restricts', () {
      final DVCronSchedule s = DVCronSchedule.parse('0 0 * * MON');
      expect(s.matches(at(2026, 4, 6, 0, 0)), isTrue);
      expect(s.matches(at(2026, 4, 7, 0, 0)), isFalse);
    });
  });

  group('the next run', () {
    test('later the same day', () {
      final DVCronSchedule s = DVCronSchedule.parse('30 2 * * *');
      expect(s.nextAfter(at(2026, 3, 4, 1, 0)), at(2026, 3, 4, 2, 30));
    });

    test('it rolls to tomorrow', () {
      final DVCronSchedule s = DVCronSchedule.parse('30 2 * * *');
      expect(s.nextAfter(at(2026, 3, 4, 3, 0)), at(2026, 3, 5, 2, 30));
    });

    test('it is strictly after, so a run does not immediately repeat', () {
      // Given the moment it just fired, the answer must be the following
      // occurrence. Returning the same instant makes a scheduler spin.
      final DVCronSchedule s = DVCronSchedule.parse('30 2 * * *');
      expect(s.nextAfter(at(2026, 3, 4, 2, 30)), at(2026, 3, 5, 2, 30));
    });

    test('it crosses a month boundary', () {
      final DVCronSchedule s = DVCronSchedule.parse('0 0 1 * *');
      expect(s.nextAfter(at(2026, 1, 15, 0, 0)), at(2026, 2, 1, 0, 0));
    });

    test('it crosses a year boundary', () {
      final DVCronSchedule s = DVCronSchedule.parse('0 0 1 1 *');
      expect(s.nextAfter(at(2026, 6, 1, 0, 0)), at(2027, 1, 1, 0, 0));
    });

    test('the 29th of February resolves to a leap year', () {
      // A date that exists once in four years is where a naive day-by-day
      // search either loops forever or silently gives up.
      final DVCronSchedule s = DVCronSchedule.parse('0 0 29 2 *');
      expect(s.nextAfter(at(2026, 3, 1, 0, 0)), at(2028, 2, 29, 0, 0));
    });

    test('a date that can never occur returns null rather than hanging', () {
      // The 31st of February. A search with no bound runs forever on it.
      final DVCronSchedule s = DVCronSchedule.parse('0 0 31 2 *');
      expect(s.nextAfter(at(2026, 1, 1, 0, 0)), isNull);
    });
  });

  group('rejecting nonsense', () {
    test('the wrong number of fields', () {
      expect(() => DVCronSchedule.parse('* * *'), throwsFormatException);
      expect(() => DVCronSchedule.parse('* * * * * *'), throwsFormatException);
      expect(() => DVCronSchedule.parse(''), throwsFormatException);
    });

    test('a value outside its field', () {
      // 61 minutes or a 13th month never matches, so a job with one silently
      // never runs. Refusing at parse time turns that into a build failure.
      expect(() => DVCronSchedule.parse('61 * * * *'), throwsFormatException);
      expect(() => DVCronSchedule.parse('* 24 * * *'), throwsFormatException);
      expect(() => DVCronSchedule.parse('* * 32 * *'), throwsFormatException);
      expect(() => DVCronSchedule.parse('* * * 13 *'), throwsFormatException);
      expect(() => DVCronSchedule.parse('* * * * 8'), throwsFormatException);
    });

    test('a backwards range', () {
      expect(() => DVCronSchedule.parse('* 17-9 * * *'), throwsFormatException);
    });

    test('a zero or negative step', () {
      expect(() => DVCronSchedule.parse('*/0 * * * *'), throwsFormatException);
      expect(() => DVCronSchedule.parse('*/-1 * * * *'), throwsFormatException);
    });

    test('an unknown shorthand', () {
      expect(() => DVCronSchedule.parse('@sometimes'), throwsFormatException);
    });

    test('a name that is not a month or day', () {
      expect(() => DVCronSchedule.parse('0 0 * FOO *'), throwsFormatException);
    });
  });
}
