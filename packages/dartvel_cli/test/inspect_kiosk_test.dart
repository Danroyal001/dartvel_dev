// `dartvel inspect kiosk`.
//
// The specification: the effective policy per target and per kiosk window,
// with the source of each value. Every kiosk the device can enter is visible
// here, because DVWindowKiosk.policy names a declared policy and a profile's
// kiosk entry goes over the section. Nothing printed any of it: doctor said
// whether the declaration could be honoured, and the answer to "what does
// the front-desk build boot into" was reading three YAML maps by hand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/inspect_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pubspec = '''
name: kiosk_app
dartvel:
  kiosk:
    enabled: true
    scope: device
    home: /welcome
    exit:
      method: pin
      pin: secret:KIOSK_PIN
    session:
      idleTimeout: 60s
    policies:
      customerDisplay:
        home: /customer
        scope: display
  deviceProfiles:
    frontDesk:
      kiosk:
        home: /front
    warehouse:
      arch: arm64
''';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _homePage(BuildContext context) => const DVText('hi');
''';

Directory project({String pubspec = _pubspec}) {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_inspect_kiosk_');
  addTearDown(() => root.deleteSync(recursive: true));
  final File page = File(p.join(root.path, 'lib', 'pages', 'index.page.dart'));
  page.parent.createSync(recursive: true);
  page.writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
  return root;
}

Future<String> run(List<String> args, Directory root) async {
  final Directory previous = Directory.current;
  Directory.current = root;
  final StringBuffer out = StringBuffer();
  try {
    await runZoned(
      () async {
        final CommandRunner<void> runner =
            CommandRunner<void>('dartvel', 'Test runner')..addCommand(InspectCommand());
        await runner.run(<String>['inspect', ...args]);
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone _, ZoneDelegate __, Zone ___, String line) => out.writeln(line),
      ),
    );
  } finally {
    Directory.current = previous;
  }
  return out.toString();
}

Map<String, Object?> asMap(Object? o) => (o! as Map).cast<String, Object?>();

void main() {
  test('the device policy carries every value with where it came from', () async {
    final Map<String, Object?> json = asMap(jsonDecode(await run(<String>['kiosk', '--json'], project())));
    final Map<String, Object?> device = asMap(json['device']);
    final Map<String, Object?> values = asMap(device['values']);
    final Map<String, Object?> sources = asMap(device['sources']);

    expect(values['home'], '/welcome');
    expect(sources['home'], 'section');
    expect(values['exit.method'], 'pin');
    expect(sources['exit.method'], 'section');
    expect(values['session.idleTimeout'], '60s');
    expect(values['session.idleWarning'], '15s');
    expect(sources['session.idleWarning'], 'default');
    expect(values['scope'], 'device');
    // The secret's name is a value; the secret is not.
    expect(values['exit.pin'], 'secret:KIOSK_PIN');
  });

  test('--device-profile puts the profile\'s kiosk entry over the section', () async {
    final Map<String, Object?> json =
        asMap(jsonDecode(await run(<String>['kiosk', '--json', '--device-profile', 'frontDesk'], project())));
    final Map<String, Object?> device = asMap(json['device']);
    expect(json['profile'], 'frontDesk');
    expect(asMap(device['values'])['home'], '/front');
    expect(asMap(device['sources'])['home'], 'profile:frontDesk');
    expect(asMap(device['sources'])['exit.method'], 'section');
  });

  test('a profile that declares no kiosk changes nothing, and is said', () async {
    final Map<String, Object?> json =
        asMap(jsonDecode(await run(<String>['kiosk', '--json', '--device-profile', 'warehouse'], project())));
    expect(asMap(asMap(json['device'])['values'])['home'], '/welcome');
    expect(json['profileOverrides'], isFalse);
  });

  test('every named policy is a kiosk window, the section under it', () async {
    final Map<String, Object?> json = asMap(jsonDecode(await run(<String>['kiosk', '--json'], project())));
    final Map<String, Object?> windows = asMap(json['windows']);
    final Map<String, Object?> customer = asMap(windows['customerDisplay']);
    expect(asMap(customer['values'])['home'], '/customer');
    expect(asMap(customer['sources'])['home'], 'policy:customerDisplay');
    expect(asMap(customer['values'])['scope'], 'display');
    expect(asMap(customer['values'])['exit.method'], 'pin');
    expect(asMap(customer['sources'])['exit.method'], 'section');
  });

  test('per target, what the policy becomes', () async {
    final Map<String, Object?> json = asMap(jsonDecode(await run(<String>['kiosk', '--json'], project())));
    final Map<String, Object?> targets = asMap(json['targets']);
    expect(asMap(targets['sonyELinux'])['strength'], 'device');
    expect(asMap(targets['linuxDesktop'])['strength'], 'supervised');
    expect(asMap(targets['macos'])['strength'], 'fullscreenOnly');
    expect(asMap(targets['watch'])['supported'], isFalse);
    expect(asMap(targets['linuxDesktop'])['codes'], isA<List<Object?>>());
  });

  test('the text form reads the same', () async {
    final String text = await run(<String>['kiosk'], project());
    expect(text, contains('kiosk (device scope)'));
    expect(text, contains('home'));
    expect(text, contains('/welcome'));
    expect(text, contains('(section)'));
    expect(text, contains('(default)'));
    expect(text, contains('customerDisplay'));
    expect(text, contains('linuxDesktop'));
    expect(text, contains('supervised'));
  });

  test('a project with no kiosk says so', () async {
    final String text = await run(<String>['kiosk'], project(pubspec: 'name: kiosk_app\n'));
    expect(text, contains('kiosk: none declared'));
    final Map<String, Object?> json =
        asMap(jsonDecode(await run(<String>['kiosk', '--json'], project(pubspec: 'name: kiosk_app\n'))));
    expect(json['enabled'], isFalse);
  });
}
