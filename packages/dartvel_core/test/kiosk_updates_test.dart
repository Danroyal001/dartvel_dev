// When a kiosk may actually apply an update.
//
// `kiosk.updates` was documentation: three policies and a maintenance window
// nothing parsed, so every kiosk applied every update the moment it found
// one -- including the one in front of a customer at midday.
//
// The interesting cases are the ones where the wrong answer still looks
// right. A window that runs past midnight is the normal shape for a
// maintenance window and the easy one to get backwards, and an update that
// is deferred for ever because its window never opens is indistinguishable,
// from the outside, from a kiosk that is up to date.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> kiosk(Map<String, Object?> body) =>
    <String, Object?>{'kiosk': body};

DVKioskPolicy policyWith(Map<String, Object?> updates) => DVKioskPolicy.parse(
      kiosk(<String, Object?>{'enabled': true, 'updates': updates}),
    );

DateTime at(int hour, [int minute = 0]) =>
    DateTime(2026, 9, 3, hour, minute);

const DVUpdateInfo offer = DVUpdateInfo(available: true, version: '1.4.0');
const DVUpdateInfo forced =
    DVUpdateInfo(available: true, version: '1.4.0', required: true);

void main() {
  group('the declaration', () {
    test('a kiosk that says nothing about updates applies them immediately', () {
      final DVKioskPolicy policy =
          DVKioskPolicy.parse(kiosk(<String, Object?>{'enabled': true}));
      expect(policy.updatesApply, DVKioskUpdateApply.immediate);
      expect(policy.updatesWindow, isNull);
      expect(policy.problems, isEmpty);
    });

    test('the window is read as a span of the day', () {
      final DVKioskPolicy policy = policyWith(<String, Object?>{
        'apply': 'maintenanceWindow',
        'window': '02:00-04:00',
      });
      expect(policy.updatesApply, DVKioskUpdateApply.maintenanceWindow);
      expect(policy.updatesWindow!.contains(at(3)), isTrue);
      expect(policy.updatesWindow!.contains(at(5)), isFalse);
      expect(policy.problems, isEmpty);
    });

    test('a window policy with no window is refused, not silently deferred', () {
      // Otherwise the kiosk waits for a window that never opens and looks
      // exactly like a kiosk with nothing to install.
      final DVKioskPolicy policy =
          policyWith(<String, Object?>{'apply': 'maintenanceWindow'});
      expect(policy.problems, isNotEmpty);
      expect(policy.problems.join(' '), contains('window'));
    });

    test('an unreadable window is a problem, not a guess', () {
      final DVKioskPolicy policy = policyWith(<String, Object?>{
        'apply': 'maintenanceWindow',
        'window': 'overnight',
      });
      expect(policy.problems, isNotEmpty);
    });
  });

  group('a window that runs past midnight', () {
    final DVMaintenanceWindow overnight = DVMaintenanceWindow.parse('23:00-01:00')!;

    test('holds the hours either side of midnight', () {
      expect(overnight.contains(at(23, 30)), isTrue);
      expect(overnight.contains(at(0, 30)), isTrue);
    });

    test('and nothing in the working day', () {
      expect(overnight.contains(at(12)), isFalse);
      expect(overnight.contains(at(22, 59)), isFalse);
      expect(overnight.contains(at(1, 1)), isFalse);
    });

    test('opens tonight when the day is still ahead of it', () {
      expect(overnight.nextOpening(at(12)), at(23));
    });

    test('opens tomorrow when tonight is already spent', () {
      // 01:30 is past the window that opened last night, so the next one is
      // tonight's -- not one twenty-two hours in the past.
      expect(overnight.nextOpening(at(1, 30)), at(23));
    });
  });

  group('what the kiosk does with an update it has found', () {
    final DVKioskPolicy window = policyWith(<String, Object?>{
      'apply': 'maintenanceWindow',
      'window': '02:00-04:00',
    });

    test('inside the window it applies', () {
      final DVKioskUpdateDecision d = window.decideUpdate(
          update: offer, state: DVKioskState.active, now: at(3));
      expect(d.action, DVKioskUpdateAction.apply);
    });

    test('outside it defers, and names the hour it will run', () {
      final DVKioskUpdateDecision d = window.decideUpdate(
          update: offer, state: DVKioskState.active, now: at(12));
      expect(d.action, DVKioskUpdateAction.defer);
      expect(d.notBefore, DateTime(2026, 9, 4, 2));
    });

    test('a forced update outside the window resets the session first', () {
      // The specification is explicit: it does not wait for the window, and
      // it does not land on top of whatever the customer was doing.
      final DVKioskUpdateDecision d = window.decideUpdate(
          update: forced, state: DVKioskState.active, now: at(12));
      expect(d.action, DVKioskUpdateAction.resetThenApply);
      expect(d.notBefore, isNull);
    });

    test('staff mode applies only with staff present', () {
      final DVKioskPolicy staff =
          policyWith(<String, Object?>{'apply': 'staffMode'});

      expect(
        staff
            .decideUpdate(
                update: offer, state: DVKioskState.staffMode, now: at(12))
            .action,
        DVKioskUpdateAction.apply,
      );
      final DVKioskUpdateDecision waiting = staff.decideUpdate(
          update: offer, state: DVKioskState.active, now: at(12));
      expect(waiting.action, DVKioskUpdateAction.defer);
      expect(waiting.notBefore, isNull,
          reason: 'staff arrive at no particular hour');
      expect(waiting.reason, contains('staff'));
    });

    test('an immediate kiosk applies in front of whoever is standing there', () {
      // Which is right for a display with no user session, and is why it is
      // not the default for anything else.
      final DVKioskPolicy immediate =
          policyWith(<String, Object?>{'apply': 'immediate'});
      expect(
        immediate
            .decideUpdate(
                update: offer, state: DVKioskState.active, now: at(12))
            .action,
        DVKioskUpdateAction.apply,
      );
    });

    test('an update nobody is offering is not a decision to apply anything', () {
      expect(
        window
            .decideUpdate(
                update: const DVUpdateInfo(available: false),
                state: DVKioskState.active,
                now: at(3))
            .action,
        DVKioskUpdateAction.none,
      );
    });
  });
}
