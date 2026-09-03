// The generated unit, handed to systemd itself.
//
// Every other test here asserts what the generator wrote. This one asserts
// that systemd will take it, which is a different claim: a unit can contain
// exactly the lines intended and still be rejected for a directive in the
// wrong section, a misspelled key, or a duration systemd does not parse. The
// device finds that out at boot.
import 'dart:io';

import 'package:dartvel_cli/src/build/supervisor_unit.dart';
import 'package:test/test.dart';

bool get hasSystemd =>
    Process.runSync('which', <String>['systemd-analyze']).exitCode == 0;

/// Runs `systemd-analyze verify` over [unit] and returns what it said.
///
/// The unit is verified by absolute path so systemd reads this file rather
/// than one of the same name already installed on the machine.
ProcessResult verify(String unit, Directory dir) {
  final File file = File('${dir.path}/dartvel-app.service')
    ..writeAsStringSync(unit);
  // systemd complains about a world-writable unit, which the temp directory's
  // umask can make it. That is this test's doing, not the generator's.
  Process.runSync('chmod', <String>['644', file.path]);
  return Process.runSync('systemd-analyze', <String>['verify', file.path]);
}

DVSupervisorDeclaration declare(Map<String, Object?> application) =>
    DVSupervisorDeclaration.parse(
      <String, Object?>{
        'targets': <String, Object?>{
          'sony-elinux': <String, Object?>{'application': application},
        },
      },
      target: 'sony-elinux',
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dartvel-unit'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('systemd accepts the kiosk unit', () {
    final String unit = dvSystemdUnit(
      appName: 'dartvel_app',
      executable: 'flutter-drm-gbm-backend',
      installDir: '/opt/dartvel_app',
      declaration: declare(<String, Object?>{
        'autostart': true,
        'restartOnFailure': true,
        'kiosk': true,
      }),
    );

    final ProcessResult result = verify(unit, dir);

    // ExecStart names a binary that is not on this machine, and systemd says
    // so. Every other complaint is the generator's fault.
    final String complaints = <String>[result.stdout, result.stderr]
        .join('\n')
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .where((String line) => !line.contains('flutter-drm-gbm-backend'))
        .join('\n');
    expect(complaints, isEmpty, reason: 'systemd rejected the generated unit');
  }, skip: hasSystemd ? null : 'systemd-analyze is not on this machine');

  test('systemd accepts the watchdog unit, and its interval', () {
    // WatchdogSec takes a systemd time span, not a Dart Duration's toString,
    // and this is where a wrong one is caught rather than at boot.
    final String unit = dvSystemdUnit(
      appName: 'dartvel_app',
      executable: 'flutter-client',
      installDir: '/opt/dartvel_app',
      declaration: declare(<String, Object?>{
        'autostart': true,
        'restartOnFailure': true,
        'watchdog': '30s',
      }),
    );

    final ProcessResult result = verify(unit, dir);

    final String complaints = <String>[result.stdout, result.stderr]
        .join('\n')
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .where((String line) => !line.contains('flutter-client'))
        .join('\n');
    expect(complaints, isEmpty, reason: 'systemd rejected the watchdog unit');
  }, skip: hasSystemd ? null : 'systemd-analyze is not on this machine');
}
