// Reading Android's own answer about lock task.
//
// The Dart side of kiosk enforcement returns a bool. A bool that lied would
// pass any test that only read it back, so the emulator job asks the platform
// too -- and then something has to read what the platform said. This is that
// something, and it is the piece that can be wrong without anyone noticing:
// a parser that returns "held" for every input makes the second opinion
// worthless while keeping the job green.
import 'package:test/test.dart';

import '../../tool/ci/android_device_checks.dart';

// Trimmed from a real `adb shell dumpsys activity activities`.
const String _locked = '''
  mLockTaskModeState=LOCK_TASK_MODE_LOCKED
  mLockTaskPackages[0]={com.example.dartvel_example}
''';
const String _pinned = '''
  LockTaskController: mLockTaskModeState=LOCK_TASK_MODE_PINNED
''';
const String _none = '''
  mLockTaskModeState=LOCK_TASK_MODE_NONE
  mLockTaskPackages[0]={}
''';

void main() {
  _spellings();
  _samples();
  group('what the platform said', () {
    test('device owner holding the task reads as locked', () {
      expect(dvLockTaskState(_locked), DVLockTaskState.locked);
    });

    test('the screen-pinning dialog path reads as pinned', () {
      expect(dvLockTaskState(_pinned), DVLockTaskState.pinned);
    });

    test('no lock task reads as none', () {
      expect(dvLockTaskState(_none), DVLockTaskState.none);
    });

    test('a dump that never mentions lock task is unknown, not none', () {
      // The difference matters: "none" is Android contradicting the test,
      // "unknown" is this job failing to ask. Collapsing them either fails
      // honest runs or hides dishonest ones.
      expect(dvLockTaskState('  mResumedActivity=ActivityRecord{...}\n'),
          DVLockTaskState.unknown);
    });

    test('LOCK_TASK_MODE_NONE elsewhere in the dump does not win', () {
      // Both appear: the controller's own state is the one that counts, and
      // a parser that takes the first match reports NONE for a locked device.
      const String mixed = '''
  mLockTaskModeState=LOCK_TASK_MODE_NONE
  Display #0
    mLockTaskModeState=LOCK_TASK_MODE_LOCKED
''';
      expect(dvLockTaskState(mixed), DVLockTaskState.locked);
    });
  });

  group('the disagreement worth failing on', () {
    test('the test says held and Android says none', () {
      expect(
        dvLockTaskDisagreement(held: true, state: DVLockTaskState.none),
        isNotNull,
      );
    });

    test('the test says held and Android agrees', () {
      expect(
        dvLockTaskDisagreement(held: true, state: DVLockTaskState.locked),
        isNull,
      );
      expect(
        dvLockTaskDisagreement(held: true, state: DVLockTaskState.pinned),
        isNull,
      );
    });

    test('Android was not asked, so there is nothing to disagree with', () {
      expect(
        dvLockTaskDisagreement(held: true, state: DVLockTaskState.unknown),
        isNull,
      );
    });

    test('the test says it did not hold and Android says it did', () {
      // The other direction, and the more alarming one: something is in lock
      // task that Dartvel does not believe it put there.
      expect(
        dvLockTaskDisagreement(held: false, state: DVLockTaskState.locked),
        isNotNull,
      );
    });
  });
}

// Appended: the samples, not the last reading.
//
// Reading dumpsys after the kiosk test has finished proves nothing -- the
// test releases the task before it ends, so a healthy run and a run where
// lock task never engaged both read NONE. The platform has to be asked while
// the test is still holding, which means several readings and a rule for
// reducing them.
void _samples() {
  group('the strongest thing seen while the test ran', () {
    test('one locked reading among many none readings wins', () {
      expect(
        dvStrongest(<DVLockTaskState>[
          DVLockTaskState.none,
          DVLockTaskState.locked,
          DVLockTaskState.none,
        ]),
        DVLockTaskState.locked,
      );
    });

    test('pinned beats none', () {
      expect(
        dvStrongest(<DVLockTaskState>[
          DVLockTaskState.none,
          DVLockTaskState.pinned,
        ]),
        DVLockTaskState.pinned,
      );
    });

    test('none beats unknown, because none is an answer', () {
      expect(
        dvStrongest(<DVLockTaskState>[
          DVLockTaskState.unknown,
          DVLockTaskState.none,
        ]),
        DVLockTaskState.none,
      );
    });

    test('nothing sampled at all is unknown', () {
      expect(dvStrongest(<DVLockTaskState>[]), DVLockTaskState.unknown);
    });
  });
}

// Appended: the other spelling.
//
// Sixty readings on an API 34 emulator all came back `unknown`, which means
// the parser found nothing to read -- so the second opinion was no opinion at
// all while looking like a working check. dumpsys does not always print the
// LOCK_TASK_MODE_ prefix: on several API levels the line is
// `mLockTaskModeState=LOCKED`. A parser that knows one spelling is a parser
// that silently abstains on every device that uses the other.
void _spellings() {
  group('however dumpsys spells it', () {
    test('the short spelling is read', () {
      expect(dvLockTaskState('  mLockTaskModeState=LOCKED\n'),
          DVLockTaskState.locked);
      expect(dvLockTaskState('  mLockTaskModeState=PINNED\n'),
          DVLockTaskState.pinned);
      expect(dvLockTaskState('  mLockTaskModeState=NONE\n'),
          DVLockTaskState.none);
    });

    test('a word that merely contains one of them is not a reading', () {
      // `mLockTaskPackages[0]={com.example.locked}` is not a state, and a
      // substring match would read it as one.
      expect(
        dvLockTaskState('  mLockTaskPackages[0]={com.example.locked}\n'),
        DVLockTaskState.unknown,
      );
    });
  });
}
