/// Cron expressions, evaluated.
///
/// `@DVBackendCron` and `@DVClientCron` were collected into generated metadata
/// and nothing evaluated one: a schedule was a string that travelled from an
/// annotation into a generated list and stopped there.
///
/// Five fields, in the order every crontab uses: minute, hour, day of month,
/// month, day of week.
library dartvel.scheduling.cron;

/// One parsed schedule.
class DVCronSchedule {
  DVCronSchedule._({
    required this.expression,
    required Set<int> minutes,
    required Set<int> hours,
    required Set<int> daysOfMonth,
    required Set<int> months,
    required Set<int> daysOfWeek,
    required this.dayOfMonthRestricted,
    required this.dayOfWeekRestricted,
  })  : _minutes = minutes,
        _hours = hours,
        _daysOfMonth = daysOfMonth,
        _months = months,
        _daysOfWeek = daysOfWeek;

  final String expression;
  final Set<int> _minutes;
  final Set<int> _hours;
  final Set<int> _daysOfMonth;
  final Set<int> _months;
  final Set<int> _daysOfWeek;

  /// Whether each day field was narrowed from `*`.
  ///
  /// Load-bearing for the OR rule below, which cannot be recovered from the
  /// resulting sets: a day-of-week field of `0-6` and one of `*` both expand
  /// to every day, and only one of them makes the match an OR.
  final bool dayOfMonthRestricted;
  final bool dayOfWeekRestricted;

  static const Map<String, int> _months3 = <String, int>{
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const Map<String, int> _days3 = <String, int>{
    'sun': 0, 'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6,
  };

  static const Map<String, String> _shorthands = <String, String>{
    '@yearly': '0 0 1 1 *',
    '@annually': '0 0 1 1 *',
    '@monthly': '0 0 1 * *',
    '@weekly': '0 0 * * 0',
    '@daily': '0 0 * * *',
    '@midnight': '0 0 * * *',
    '@hourly': '0 * * * *',
  };

  /// Parses [expression], throwing [FormatException] if it is not a schedule.
  ///
  /// Throwing rather than falling back to "never" or "always": a job whose
  /// expression cannot match silently never runs, and the failure surfaces
  /// weeks later as "the report stopped arriving". A build failure is the
  /// cheapest place to find it.
  static DVCronSchedule parse(String expression) {
    final String trimmed = expression.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('A cron expression cannot be empty.');
    }

    if (trimmed.startsWith('@')) {
      final String? expanded = _shorthands[trimmed.toLowerCase()];
      if (expanded == null) {
        throw FormatException(
          'Unknown cron shorthand "$trimmed". Known: '
          '${_shorthands.keys.join(', ')}.',
        );
      }
      return parse(expanded);
    }

    final List<String> fields =
        trimmed.split(RegExp(r'\s+')).where((String f) => f.isNotEmpty).toList();
    if (fields.length != 5) {
      throw FormatException(
        'A cron expression has five fields (minute hour day month weekday); '
        'got ${fields.length} in "$expression".',
      );
    }

    final Set<int> minutes = _field(fields[0], 0, 59, 'minute');
    final Set<int> hours = _field(fields[1], 0, 23, 'hour');
    final Set<int> daysOfMonth = _field(fields[2], 1, 31, 'day of month');
    final Set<int> months = _field(fields[3], 1, 12, 'month', _months3);
    // 0..7, because Sunday is spelled both ways in the wild and a scheduler
    // that knows only one skips every Sunday job written the other way.
    final Set<int> weekdays = _field(fields[4], 0, 7, 'day of week', _days3);

    return DVCronSchedule._(
      expression: trimmed,
      minutes: minutes,
      hours: hours,
      daysOfMonth: daysOfMonth,
      months: months,
      daysOfWeek: <int>{for (final int d in weekdays) d == 7 ? 0 : d},
      dayOfMonthRestricted: fields[2] != '*',
      dayOfWeekRestricted: fields[4] != '*',
    );
  }

  /// Whether [time] is an occurrence, to the minute.
  bool matches(DateTime time) {
    if (!_minutes.contains(time.minute)) return false;
    if (!_hours.contains(time.hour)) return false;
    if (!_months.contains(time.month)) return false;

    // Dart's Monday..Sunday is 1..7; cron's Sunday is 0.
    final int weekday = time.weekday == DateTime.sunday ? 0 : time.weekday;
    final bool domMatch = _daysOfMonth.contains(time.day);
    final bool dowMatch = _daysOfWeek.contains(weekday);

    // The rule people get wrong. When both day fields are restricted, cron
    // takes either -- `0 0 1 * MON` is the 1st OR a Monday. Read as an AND it
    // runs when the 1st happens to be a Monday, about once a year, which
    // looks like the scheduler being broken rather than the expression being
    // misread.
    if (dayOfMonthRestricted && dayOfWeekRestricted) {
      return domMatch || dowMatch;
    }
    return domMatch && dowMatch;
  }

  /// The first occurrence strictly after [from], or null if there is none.
  ///
  /// Strictly after, so a scheduler handed the moment it just fired gets the
  /// following occurrence rather than the same one, which would make it spin.
  ///
  /// Null rather than looping for an expression that can never match -- the
  /// 31st of February parses fine and occurs never, and an unbounded search
  /// hangs the process rather than reporting it.
  DateTime? nextAfter(DateTime from) {
    // Minute resolution, so start at the next whole minute.
    DateTime candidate = DateTime(
      from.year,
      from.month,
      from.day,
      from.hour,
      from.minute,
    ).add(const Duration(minutes: 1));

    // Five years of minutes is far past any real schedule, and the day-level
    // skip below means most of these iterations never happen. The 29th of
    // February needs four years of headroom on its own.
    final DateTime limit = DateTime(from.year + 5, from.month, from.day);

    while (candidate.isBefore(limit)) {
      if (!_months.contains(candidate.month)) {
        // Skip to the first of the next month rather than a minute at a time.
        candidate = candidate.month == 12
            ? DateTime(candidate.year + 1, 1, 1)
            : DateTime(candidate.year, candidate.month + 1, 1);
        continue;
      }
      if (!_dayMatches(candidate)) {
        candidate = DateTime(candidate.year, candidate.month, candidate.day)
            .add(const Duration(days: 1));
        continue;
      }
      if (!_hours.contains(candidate.hour)) {
        candidate = DateTime(
          candidate.year,
          candidate.month,
          candidate.day,
          candidate.hour,
        ).add(const Duration(hours: 1));
        continue;
      }
      if (!_minutes.contains(candidate.minute)) {
        candidate = candidate.add(const Duration(minutes: 1));
        continue;
      }
      return candidate;
    }
    return null;
  }

  bool _dayMatches(DateTime time) {
    final int weekday = time.weekday == DateTime.sunday ? 0 : time.weekday;
    final bool domMatch = _daysOfMonth.contains(time.day);
    final bool dowMatch = _daysOfWeek.contains(weekday);
    if (dayOfMonthRestricted && dayOfWeekRestricted) {
      return domMatch || dowMatch;
    }
    return domMatch && dowMatch;
  }

  /// Expands one field into the values it matches.
  static Set<int> _field(
    String field,
    int min,
    int max,
    String label, [
    Map<String, int>? names,
  ]) {
    final Set<int> out = <int>{};
    for (final String part in field.split(',')) {
      if (part.isEmpty) {
        throw FormatException('Empty $label value in "$field".');
      }

      String body = part;
      int step = 1;
      final int slash = part.indexOf('/');
      if (slash >= 0) {
        body = part.substring(0, slash);
        final String stepText = part.substring(slash + 1);
        final int? parsed = int.tryParse(stepText);
        if (parsed == null || parsed < 1) {
          // A step of zero or less matches nothing or loops, and either way
          // the job never runs.
          throw FormatException(
            'A cron step must be a positive whole number; got "$stepText" in '
            'the $label field.',
          );
        }
        step = parsed;
      }

      int start;
      int end;
      if (body == '*') {
        start = min;
        end = max;
      } else {
        final int dash = body.indexOf('-', 1);
        if (dash >= 0) {
          start = _value(body.substring(0, dash), min, max, label, names);
          end = _value(body.substring(dash + 1), min, max, label, names);
          if (end < start) {
            // Wrapping ranges are not portable and are far more often a typo
            // than an intent.
            throw FormatException(
              'A cron range must not run backwards; got "$body" in the $label '
              'field.',
            );
          }
        } else {
          start = _value(body, min, max, label, names);
          end = slash >= 0 ? max : start;
        }
      }

      for (int value = start; value <= end; value += step) {
        out.add(value);
      }
    }

    if (out.isEmpty) {
      throw FormatException('The $label field "$field" matches nothing.');
    }
    return out;
  }

  static int _value(
    String text,
    int min,
    int max,
    String label,
    Map<String, int>? names,
  ) {
    final String lower = text.trim().toLowerCase();
    // A name where one is allowed, so JAN and MON read as they do in a
    // crontab; a name in a field that has none is a typo, not a zero.
    int? value = int.tryParse(lower) ?? names?[lower];
    if (value == null) {
      throw FormatException(
        '"$text" is not a valid $label value.',
      );
    }
    if (value < min || value > max) {
      // A 61st minute or a 13th month never matches, so a job carrying one
      // silently never runs.
      throw FormatException(
        '$label must be between $min and $max; got $value.',
      );
    }
    return value;
  }
}
