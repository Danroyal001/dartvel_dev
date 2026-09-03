import 'runtime.dart' show DVKioskState;

/// When a kiosk is allowed to apply an update it has found.
///
/// `dartvel.kiosk.updates.apply`. The default is [immediate] because a build
/// that says nothing about updates has said nothing to defer them, but it is
/// the wrong answer for most kiosks: an update applied at midday restarts the
/// application in front of whoever is standing at it.
enum DVKioskUpdateApply {
  /// Apply on discovery, whatever is on screen. Right for a display with no
  /// user session, and for nothing else.
  immediate,

  /// Apply only inside `updates.window`.
  maintenanceWindow,

  /// Apply only while staff are present, so somebody is there if it goes
  /// wrong.
  staffMode,
}

/// A span of the day, as `HH:MM-HH:MM`.
///
/// A maintenance window normally runs past midnight, which is why this is a
/// span of the clock rather than of time: `23:00-01:00` is two hours, not a
/// negative twenty-two.
class DVMaintenanceWindow {
  const DVMaintenanceWindow({required this.startMinute, required this.endMinute});

  /// Minutes past midnight at which the window opens.
  final int startMinute;

  /// Minutes past midnight at which it closes. Less than [startMinute] when
  /// the window runs into the next day.
  final int endMinute;

  /// Whether the window runs past midnight.
  bool get wrapsMidnight => endMinute <= startMinute;

  /// Reads `02:00-04:00`. Null when it cannot be read, so a caller can say
  /// so rather than fall back to a window it invented.
  static DVMaintenanceWindow? parse(Object? raw) {
    if (raw == null) return null;
    final List<String> halves = raw.toString().trim().split('-');
    if (halves.length != 2) return null;
    final int? start = _minutesOf(halves[0]);
    final int? end = _minutesOf(halves[1]);
    if (start == null || end == null) return null;
    return DVMaintenanceWindow(startMinute: start, endMinute: end);
  }

  static int? _minutesOf(String raw) {
    final List<String> parts = raw.trim().split(':');
    if (parts.length != 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// Whether [when] falls inside the window.
  bool contains(DateTime when) {
    final int minute = when.hour * 60 + when.minute;
    if (!wrapsMidnight) return minute >= startMinute && minute < endMinute;
    return minute >= startMinute || minute < endMinute;
  }

  /// When the window next opens, at or after [when].
  ///
  /// [when] inside the window returns [when]: the window is open, and an
  /// update that waited for the next opening would sit through the one it is
  /// already in.
  DateTime nextOpening(DateTime when) {
    if (contains(when)) return when;
    final DateTime today = DateTime(
      when.year,
      when.month,
      when.day,
      startMinute ~/ 60,
      startMinute % 60,
    );
    if (!today.isBefore(when)) return today;
    return today.add(const Duration(days: 1));
  }

  @override
  String toString() => '${_hhmm(startMinute)}-${_hhmm(endMinute)}';

  static String _hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';
}

/// An update a kiosk has been offered.
///
/// The kiosk decision is made in core, where the update runtime is not, so
/// this is the little of an offer the decision actually turns on.
class DVUpdateOffer {
  const DVUpdateOffer({
    required this.version,
    this.available = true,
    this.required = false,
  });

  final String? version;
  final bool available;

  /// A minimum supported version, not a new one. It does not wait.
  final bool required;
}

/// What a kiosk should do with an update it has found.
enum DVKioskUpdateAction {
  /// Nothing was offered.
  none,

  /// Apply it now.
  apply,

  /// Apply it now, after clearing whatever session is on screen -- a forced
  /// update does not land on top of a customer's half-finished order.
  resetThenApply,

  /// Not yet.
  defer,
}

/// A kiosk's answer about one update, and why.
///
/// The reason is not decoration. A deferred update and an absent update look
/// identical on a device nobody is standing at, and the difference is hours
/// of somebody's time.
class DVKioskUpdateDecision {
  const DVKioskUpdateDecision({
    required this.action,
    required this.reason,
    this.notBefore,
  });

  final DVKioskUpdateAction action;

  /// In the policy's own terms, for an operator reading a fleet report.
  final String reason;

  /// When the kiosk will apply it, when that is known. Null for a deferral
  /// waiting on something that has no hour -- staff arriving, for one.
  final DateTime? notBefore;
}

/// The decision itself, shared by device and display scope.
DVKioskUpdateDecision dvDecideKioskUpdate({
  required DVKioskUpdateApply apply,
  required DVMaintenanceWindow? window,
  required DVUpdateOffer update,
  required DVKioskState state,
  required DateTime now,
}) {
  if (!update.available) {
    return const DVKioskUpdateDecision(
      action: DVKioskUpdateAction.none,
      reason: 'no update was offered',
    );
  }
  if (apply == DVKioskUpdateApply.immediate) {
    return const DVKioskUpdateDecision(
      action: DVKioskUpdateAction.apply,
      reason: 'updates.apply is immediate',
    );
  }
  final bool allowed = switch (apply) {
    DVKioskUpdateApply.immediate => true,
    DVKioskUpdateApply.staffMode => state == DVKioskState.staffMode,
    DVKioskUpdateApply.maintenanceWindow => window?.contains(now) ?? false,
  };
  if (allowed) {
    return DVKioskUpdateDecision(
      action: DVKioskUpdateAction.apply,
      reason: apply == DVKioskUpdateApply.staffMode
          ? 'staff are present'
          : 'inside the maintenance window $window',
    );
  }
  if (update.required) {
    // The specification is explicit: a forced update outside the window shows
    // the generated update UI and resets the session first. Holding a minimum
    // supported version until two in the morning would leave the fleet on a
    // version somebody has already decided is not fit to run.
    return const DVKioskUpdateDecision(
      action: DVKioskUpdateAction.resetThenApply,
      reason: 'the update is required, so it does not wait for the window',
    );
  }
  if (apply == DVKioskUpdateApply.staffMode) {
    return const DVKioskUpdateDecision(
      action: DVKioskUpdateAction.defer,
      reason: 'waiting for staff mode',
    );
  }
  return DVKioskUpdateDecision(
    action: DVKioskUpdateAction.defer,
    reason: 'outside the maintenance window $window',
    notBefore: window?.nextOpening(now),
  );
}
