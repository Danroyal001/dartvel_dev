// `dartvel dev` always pairs development builds.
//
// Pairing used to sit behind a dev-client flag, and a flag nobody passes is a
// feature nobody meets: the QR code that pairs a phone was printed only for
// developers who already knew to ask for it. Now every `dartvel dev` serves
// the pairing endpoint and prints the code, runs the local app as it always
// did when there is a device to run it on, and when there is none keeps
// serving the paired devices instead of exiting.
import 'dart:async';

import 'package:args/args.dart';
import 'package:dartvel_cli/src/commands/dev_command.dart';
import 'package:test/test.dart';

Map<String, Object?> _device(String id, String platform) => <String, Object?>{
  'id': id,
  'name': id,
  'targetPlatform': platform,
};

void main() {
  group('the command line', () {
    test('there is no dev-client flag to forget', () {
      final ArgParser parser = DevCommand().argParser;
      expect(parser.options.keys, isNot(contains('dev-client')));
      expect(
        () => parser.parse(<String>['--dev' '-client']),
        throwsA(isA<ArgParserException>()),
      );
    });

    test('the pairing port is still chosen on the command line', () {
      final ArgResults results = DevCommand().argParser.parse(<String>[
        '--pairing-port',
        '9797',
      ]);
      expect(results['pairing-port'], '9797');
    });
  });

  group('which local app runs beside pairing', () {
    test('a named device runs, whatever is connected', () {
      expect(
        dvDevLocalDevice(
          named: 'chrome',
          detected: <Map<String, Object?>>[_device('emulator-5554', 'android')],
          interactive: false,
        ),
        'chrome',
      );
    });

    test('the one connected device runs, as it always did', () {
      expect(
        dvDevLocalDevice(
          named: null,
          detected: <Map<String, Object?>>[_device('linux', 'linux-x64')],
          interactive: false,
        ),
        'linux',
      );
    });

    test('with no device, no local app runs: pairing is what is served', () {
      expect(
        dvDevLocalDevice(
          named: null,
          detected: const <Map<String, Object?>>[],
          interactive: true,
        ),
        isNull,
      );
    });

    test('several devices and nobody to ask runs none, rather than waiting on '
        'a prompt nobody can answer', () {
      expect(
        dvDevLocalDevice(
          named: null,
          detected: <Map<String, Object?>>[
            _device('linux', 'linux-x64'),
            _device('chrome', 'web-javascript'),
          ],
          interactive: false,
        ),
        isNull,
      );
    });

    test('several devices at a terminal are chosen from', () {
      expect(
        dvDevLocalDevice(
          named: null,
          detected: <Map<String, Object?>>[
            _device('linux', 'linux-x64'),
            _device('chrome', 'web-javascript'),
          ],
          interactive: true,
          choose: (List<Map<String, Object?>> devices) => devices[1]['id']
              as String?,
        ),
        'chrome',
      );
    });
  });

  group('how long dartvel dev runs', () {
    test('while pairing is served, the local app and the backend exiting do '
        'not end it', () async {
      final Completer<int> app = Completer<int>();
      final Completer<int> backend = Completer<int>();
      final Completer<void> interrupted = Completer<void>();
      bool finished = false;
      unawaited(
        dvDevWaitForExit(
          localApp: app.future,
          backend: backend.future,
          pairing: true,
          interrupted: interrupted.future,
        ).then((_) => finished = true),
      );
      app.complete(0);
      backend.complete(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(finished, isFalse);

      interrupted.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(finished, isTrue);
    });

    test('with no pairing server, the local app exiting ends it as before',
        () async {
      final Completer<int> app = Completer<int>();
      bool finished = false;
      unawaited(
        dvDevWaitForExit(
          localApp: app.future,
          pairing: false,
          interrupted: Completer<void>().future,
        ).then((_) => finished = true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(finished, isFalse);
      app.complete(0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(finished, isTrue);
    });
  });
}
