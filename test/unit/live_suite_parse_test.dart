// What the machine reporter said, and what this makes of it.
//
// There was no test for this. It had been changed four times in three days
// on the strength of reading CI logs, because there was no other way to
// change it: nothing could be asserted without a macOS runner and a suite
// that fails one run in five. Every one of those changes was a guess that
// took a CI cycle to check, and one of them added a diagnostic that could
// not answer the question it was added for.
//
// A recorded stream is fed to the parser here instead. The shapes below are
// transcribed from real runs.
import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/ci/live_suite.dart';

/// One line of the `--machine` stream.
String _event(Map<String, Object?> event) => jsonEncode(event);

/// The stream a suite produces when every test passes.
String _clean() => <String>[
      _event(<String, Object?>{'type': 'start'}),
      _event(<String, Object?>{
        'type': 'testStart',
        'test': <String, Object?>{'id': 1, 'name': 'dialogs save'},
      }),
      _event(<String, Object?>{
        'type': 'testDone',
        'testID': 1,
        'result': 'success',
      }),
      _event(<String, Object?>{'type': 'done', 'success': true}),
    ].join('\n');

/// The stream a suite produces when the process is closed while running:
/// the fixture reports a non-success testDone, no error is ever emitted,
/// and a done event arrives all the same.
String _fixtureDied() => <String>[
      _event(<String, Object?>{'type': 'start'}),
      _event(<String, Object?>{
        'type': 'testStart',
        'test': <String, Object?>{'id': 1, 'name': 'dialogs save'},
      }),
      _event(<String, Object?>{
        'type': 'testDone',
        'testID': 1,
        'result': 'success',
      }),
      _event(<String, Object?>{
        'type': 'testStart',
        'test': <String, Object?>{'id': 2, 'name': '(tearDownAll)'},
      }),
      _event(<String, Object?>{
        'type': 'testDone',
        'testID': 2,
        'result': 'error',
      }),
      _event(<String, Object?>{'type': 'done', 'success': false}),
    ].join('\n');

/// A real test failing, with the reporter explaining why.
String _realFailure() => <String>[
      _event(<String, Object?>{'type': 'start'}),
      _event(<String, Object?>{
        'type': 'testStart',
        'test': <String, Object?>{'id': 1, 'name': 'dialogs save'},
      }),
      _event(<String, Object?>{
        'type': 'error',
        'testID': 1,
        'error': 'Expected: true\n  Actual: <false>',
        'stackTrace': 'test/macos_dialogs_live_test.dart 101:7',
      }),
      _event(<String, Object?>{
        'type': 'testDone',
        'testID': 1,
        'result': 'failure',
      }),
      _event(<String, Object?>{'type': 'done', 'success': false}),
    ].join('\n');

/// The shape a macOS panel death produces at the end of a suite.
///
/// Real tests and the closing fixture all marked failed, no error event ever
/// emitted for any of them, and a verdict all the same. Transcribed from the
/// run on 2026-09-07 that reported five dialog tests and a tearDownAll,
/// where the run before it had passed twenty-seven.
String _diedWithRealTestsMarked() => <String>[
      _event(<String, Object?>{'type': 'start'}),
      _event(<String, Object?>{
        'type': 'testStart',
        'test': <String, Object?>{'id': 1, 'name': 'dialogs are available'},
      }),
      _event(<String, Object?>{
        'type': 'testDone',
        'testID': 1,
        'result': 'success',
      }),
      for (int id = 2; id <= 6; id++) ...<String>[
        _event(<String, Object?>{
          'type': 'testStart',
          'test': <String, Object?>{'id': id, 'name': 'dialogs open $id'},
        }),
        _event(<String, Object?>{
          'type': 'testDone',
          'testID': id,
          'result': 'error',
        }),
      ],
      _event(<String, Object?>{
        'type': 'testStart',
        'test': <String, Object?>{'id': 7, 'name': '(tearDownAll)'},
      }),
      _event(<String, Object?>{
        'type': 'testDone',
        'testID': 7,
        'result': 'error',
      }),
      _event(<String, Object?>{'type': 'done', 'success': false}),
    ].join('\n');

DVLiveRun _parse(String machine, {String stderr = '', int exitCode = 0}) =>
    dvParseLiveSuite(
        machine: machine, stderr: stderr, exitCode: exitCode, hung: false);

void main() {
  group('a clean run', () {
    test('counts what passed and is not a death', () {
      final DVLiveRun run = _parse(_clean());

      expect(run.passed, 1);
      expect(run.failures, isEmpty);
      expect(run.diedPartway, isFalse);
    });
  });

  group('the shape this suite kept producing', () {
    test('a fixture failing with nothing attached is a death, not a failure',
        () {
      // The whole point. Two days of CI reported this as a broken save-panel
      // test, in output where the save-panel test says ok three lines above
      // the failure.
      final DVLiveRun run = _parse(_fixtureDied(), exitCode: 1);

      expect(run.passed, 1);
      expect(run.onlyFixturesFailed, isTrue);
      expect(run.diedPartway, isTrue,
          reason: 'the process went away; it is retried like the other two '
              'shapes of the same accident');
    });

    test('the fixture is the only thing reported failed', () {
      final DVLiveRun run = _parse(_fixtureDied(), exitCode: 1);

      expect(run.failures, <String>['(tearDownAll)']);
    });
  });

  group('a real failure is still a real failure', () {
    test('an error attached to it means it is not a death', () {
      // The line that matters in the other direction. If this were folded
      // into the retry as well, a genuinely broken test would be run twice
      // and then reported -- or worse, retried into a pass.
      final DVLiveRun run = _parse(_realFailure(), exitCode: 1);

      expect(run.failures, hasLength(1));
      expect(run.errorsAttached, isTrue);
      expect(run.onlyFixturesFailed, isFalse);
      expect(run.diedPartway, isFalse);
    });

    test('a fixture failing alongside a real test is not a death either', () {
      // A teardown that fails because the test before it left the world
      // broken is a consequence of the failure, not an accident.
      final DVLiveRun run =
          _parse('${_realFailure()}\n${_fixtureDied()}', exitCode: 1);

      expect(run.onlyFixturesFailed, isFalse);
    });
  });

  group('what it keeps of the process itself', () {
    test('output that is not a report is kept, not dropped', () {
      // An AppKit warning or a native log is the only account of what
      // happened when the reporter attaches no error to anything.
      final DVLiveRun run = _parse(
          '${_clean()}\nobjc[123]: a native warning nobody parsed');

      expect(run.lines.join('\n'), isNot(contains('a native warning')),
          reason: 'it belongs to the run, not to a named test');
      expect(run.verdict, isTrue);
    });

    test('a stream with no done event at all is a death', () {
      final String truncated = _clean()
          .split('\n')
          .where((String line) => !line.contains('"done"'))
          .join('\n');

      expect(_parse(truncated).diedPartway, isTrue);
    });

    test('the harness saying the shell ended is a death', () {
      expect(
        _parse(_clean(), stderr: 'Shell subprocess ended cleanly. Did main() '
                'call exit()?')
            .diedPartway,
        isTrue,
      );
    });
  });

  group('failures with nothing attached to any of them', () {
    test('are a death even when real tests are among them', () {
      // onlyFixturesFailed covered the case where the process died late
      // enough that only the closing fixture was left. It can die a moment
      // earlier and take five real tests with it, and that arrived looking
      // like five broken dialogs -- reported as a failure on a suite whose
      // previous run passed twenty-seven.
      //
      // A test that genuinely fails carries an error. Every failure carrying
      // none is the accident, not a fault.
      final DVLiveRun run = _parse(_diedWithRealTestsMarked());

      expect(run.passed, 1);
      expect(run.failures.length, 6);
      expect(run.errorsAttached, isFalse);
      expect(run.diedPartway, isTrue);
    });

    test('a real failure with an error is still a failure', () {
      // The check is only worth having if it does not swallow the thing it
      // is meant to report.
      final DVLiveRun run = _parse(_realFailure());

      expect(run.errorsAttached, isTrue);
      expect(run.diedPartway, isFalse);
    });
  });
}
