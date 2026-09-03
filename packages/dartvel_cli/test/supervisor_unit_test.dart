// Boot-to-app: the unit that starts the application and keeps it started.
//
// `autostart` and `restartOnFailure` were declaration keys nothing read, so
// an image built from them booted to a login prompt. The supervisor on an
// eLinux image is systemd, and the unit is the whole of what "boots into the
// app" means there.
//
// The failures worth testing are the ones that produce a running system that
// is subtly wrong: a watchdog shorter than the heartbeat restarts a healthy
// application for ever and looks exactly like a crash loop, and a unit with
// no [Install] section installs, starts by hand, and never comes up at boot.
import 'dart:io';

import 'package:dartvel_cli/src/build/supervisor_unit.dart';
import 'package:test/test.dart';

Map<String, Object?> declaration(Map<String, Object?> application) =>
    <String, Object?>{
      'targets': <String, Object?>{
        'sony-elinux': <String, Object?>{'application': application},
      },
    };

DVSupervisorDeclaration parse(Map<String, Object?> application) =>
    DVSupervisorDeclaration.parse(
      declaration(application),
      target: 'sony-elinux',
    );

String unitFor(Map<String, Object?> application) => dvSystemdUnit(
      appName: 'dartvel_app',
      executable: 'flutter-drm-gbm-backend',
      installDir: '/opt/dartvel_app',
      declaration: parse(application),
    );

void main() {
  group('the declaration', () {
    test('a target that says nothing does not autostart', () {
      final DVSupervisorDeclaration d = DVSupervisorDeclaration.parse(
        <String, Object?>{},
        target: 'sony-elinux',
      );
      expect(d.autostart, isFalse);
      expect(d.restartOnFailure, isFalse);
      expect(d.problems, isEmpty);
    });

    test('autostart and restartOnFailure are read where the spec puts them', () {
      final DVSupervisorDeclaration d = parse(<String, Object?>{
        'autostart': true,
        'restartOnFailure': true,
        'kiosk': true,
      });
      expect(d.autostart, isTrue);
      expect(d.restartOnFailure, isTrue);
      expect(d.kiosk, isTrue);
    });

    test('they are also read at the top of the target, as the bundle example writes them', () {
      // dartvel.targets.sony-elinux.autostart in one example and
      // .application.autostart in another; both are in the specification and
      // a build that honoured only one would silently not boot.
      final DVSupervisorDeclaration d = DVSupervisorDeclaration.parse(
        <String, Object?>{
          'targets': <String, Object?>{
            'sony-elinux': <String, Object?>{'autostart': true, 'kiosk': true},
          },
        },
        target: 'sony-elinux',
      );
      expect(d.autostart, isTrue);
      expect(d.kiosk, isTrue);
    });

    test('a watchdog with no restart is a problem, not a supervised app', () {
      // A missed heartbeat stops the application and Restart=no leaves it
      // stopped: the device is dark until somebody visits it.
      final DVSupervisorDeclaration d = parse(<String, Object?>{
        'autostart': true,
        'restartOnFailure': false,
        'watchdog': '30s',
      });
      expect(d.problems, isNotEmpty);
      expect(d.problems.join(' '), contains('watchdog'));
    });

    test('an unreadable watchdog is a problem rather than an ignored key', () {
      final DVSupervisorDeclaration d = parse(<String, Object?>{
        'autostart': true,
        'restartOnFailure': true,
        'watchdog': 'sometimes',
      });
      expect(d.problems, isNotEmpty);
      expect(d.watchdog, isNull);
    });
  });

  group('the unit', () {
    test('starts the embedder from the install directory', () {
      final String unit = unitFor(<String, Object?>{'autostart': true});
      expect(unit, contains('ExecStart=/opt/dartvel_app/flutter-drm-gbm-backend'));
      expect(unit, contains('WorkingDirectory=/opt/dartvel_app'));
    });

    test('an autostarting app is wanted by a boot target', () {
      final String unit = unitFor(<String, Object?>{'autostart': true});
      expect(unit, contains('[Install]'));
      expect(unit, contains('WantedBy=multi-user.target'));
    });

    test('an app that does not autostart has nothing to enable', () {
      // A unit with an [Install] section that is not meant to boot would be
      // enabled by the image build and start anyway.
      final String unit = unitFor(<String, Object?>{'autostart': false});
      expect(unit, isNot(contains('[Install]')));
    });

    test('restartOnFailure says which failures', () {
      expect(
        unitFor(<String, Object?>{'autostart': true, 'restartOnFailure': true}),
        contains('Restart=always'),
      );
      expect(
        unitFor(<String, Object?>{'autostart': true, 'restartOnFailure': false}),
        contains('Restart=no'),
      );
    });

    test('a kiosk waits for the display device before it starts', () {
      // A DRM embedder that starts before udev has settled finds no card and
      // exits, and with Restart=always that is a boot loop.
      final String unit = unitFor(<String, Object?>{
        'autostart': true,
        'restartOnFailure': true,
        'kiosk': true,
      });
      expect(unit, contains('systemd-udev-settle.service'));
    });

    test('a declared watchdog makes the unit expect the heartbeat', () {
      final String unit = unitFor(<String, Object?>{
        'autostart': true,
        'restartOnFailure': true,
        'watchdog': '30s',
      });
      expect(unit, contains('Type=notify'));
      expect(unit, contains('WatchdogSec=30s'));
    });

    test('no watchdog means systemd is not waiting for a heartbeat', () {
      // Type=notify without sd_notify leaves systemd waiting for a readiness
      // notification that never comes, and the unit times out on a working
      // application.
      final String unit = unitFor(<String, Object?>{'autostart': true});
      expect(unit, contains('Type=simple'));
      expect(unit, isNot(contains('WatchdogSec')));
    });
  });

  group('writing it beside the bundle', () {
    late Directory root;
    late String bundle;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dartvel-supervisor');
      bundle = '${root.path}/build/elinux/x64/release/bundle';
      Directory(bundle).createSync(recursive: true);
    });
    tearDown(() => root.deleteSync(recursive: true));

    void pubspec(String dartvel) => File('${root.path}/pubspec.yaml')
        .writeAsStringSync('name: shop_kiosk\n$dartvel');

    test('a declared autostart puts a unit in the bundle', () {
      pubspec('''
dartvel:
  targets:
    sony-elinux:
      application: { autostart: true, restartOnFailure: true, kiosk: true }
''');

      final DVSupervisorWrite result = dvWriteSupervisorUnit(
        root.path,
        bundle,
        executable: 'flutter-drm-gbm-backend',
      );

      expect(result.written, contains('shop_kiosk.service'));
      final String unit = File('$bundle/shop_kiosk.service').readAsStringSync();
      expect(unit, contains('WantedBy=multi-user.target'));
      expect(unit, contains('Restart=always'));
      expect(result.problems, isEmpty);
    });

    test('a target that declares no supervision gets no unit', () {
      // An image that installs a unit nobody asked for starts the application
      // at boot on a device meant to boot to a desktop.
      pubspec('dartvel:\n  targets:\n    sony-elinux: { architecture: x64 }\n');

      final DVSupervisorWrite result = dvWriteSupervisorUnit(
        root.path,
        bundle,
        executable: 'flutter-client',
      );

      expect(result.written, isEmpty);
      expect(File('$bundle/shop_kiosk.service').existsSync(), isFalse);
    });

    test('the declaration\'s problems come back rather than being written out', () {
      pubspec('''
dartvel:
  targets:
    sony-elinux:
      application: { autostart: true, restartOnFailure: false, watchdog: 30s }
''');

      final DVSupervisorWrite result = dvWriteSupervisorUnit(
        root.path,
        bundle,
        executable: 'flutter-client',
      );

      expect(result.problems, isNotEmpty);
      expect(result.written, contains('shop_kiosk.service'),
          reason: 'the unit is still written; the problem is reported beside it');
    });
  });
}
