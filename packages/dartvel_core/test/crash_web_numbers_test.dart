// A crash report on the web: the id and the fingerprint, compiled to
// JavaScript and run, compared with this VM.
//
// Web integers are doubles and web shifts are 32-bit. Two failures followed,
// and neither shows on the VM that every other test here runs on:
//
//  * `1 << 32` is 0 in JavaScript, so a report id asked Random for a number
//    below 0 and threw. Installation starts a session with one, so a web
//    application's startup threw before its first frame -- which the site
//    build reported as "Captured 0 of N routes", not as a crash reporter bug.
//  * a product past 2^53 is rounded, so the fingerprint hash was a different
//    number on the web: one bug reported from a browser and from a phone
//    became two groups, each looking complete.
//
// So this compiles a probe with dart2js, runs it under node, and holds the
// web's answers to the VM's.
@TestOn('vm')
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:test/test.dart';

const String _stack =
    '#0      CheckoutController.pay (package:shop/checkout/controller.dart:88:7)\n'
    '#1      PayButton.onPressed (package:shop/checkout/pay_button.dart:31:12)\n'
    '#2      GestureRecognizer.invokeCallback (package:flutter/src/gestures/recognizer.dart:315:24)\n'
    '#3      ProfilePage.build (package:shop/profile/page.dart:40:3)';

final String _probe = '''
import 'dart:convert';

import 'package:dartvel_core/src/crashes/crash_report.dart';

void main() {
  final Map<String, Object?> out = <String, Object?>{};
  try {
    final Set<String> ids = <String>{
      for (int i = 0; i < 50; i++) dvCrashReportId(DateTime.utc(2026, 9, 14)),
    };
    out['ids'] = ids.length;
  } catch (error) {
    out['idError'] = '\$error';
  }
  final List<DVCrashFrame> frames = DVCrashFrame.parse(${jsonEncode(_stack)});
  out['fingerprint'] =
      DVCrashFingerprint.of(errorType: 'StateError', frames: frames);
  out['override'] = DVCrashFingerprint.of(
      errorType: 'StateError', frames: frames, override: 'checkout-helper');
  print('PROBE \${jsonEncode(out)}');
}
''';

void main() {
  final bool hasNode = Process.runSync('which', <String>['node']).exitCode == 0;

  test(
    'on the web a report id does not throw, and a fingerprint is the VM\'s',
    () async {
      final Uri core = (await Isolate.resolvePackageUri(
        Uri.parse('package:dartvel_core/dartvel.dart'),
      ))!;
      final String package = File.fromUri(core).parent.parent.path;
      final Directory work =
          Directory.systemTemp.createTempSync('dv_crash_web_numbers_');
      addTearDown(() => work.deleteSync(recursive: true));
      final File probe = File('${work.path}/probe.dart')
        ..writeAsStringSync(_probe);

      final ProcessResult compiled = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          'compile',
          'js',
          '--packages=$package/.dart_tool/package_config.json',
          '-O2',
          '-o',
          '${work.path}/probe.js',
          probe.path,
        ],
      );
      expect(compiled.exitCode, 0,
          reason: 'dart2js failed:\n${compiled.stdout}\n${compiled.stderr}');

      final ProcessResult ran =
          await Process.run('node', <String>['${work.path}/probe.js']);
      final String? line = const LineSplitter()
          .convert('${ran.stdout}')
          .where((String l) => l.startsWith('PROBE '))
          .firstOrNull;
      expect(line, isNotNull,
          reason: 'the probe did not run:\n${ran.stdout}\n${ran.stderr}');
      final Map<String, Object?> web =
          jsonDecode(line!.substring('PROBE '.length)) as Map<String, Object?>;

      final List<DVCrashFrame> frames = DVCrashFrame.parse(_stack);
      expect(web['idError'], isNull);
      expect(web['ids'], 50, reason: 'report ids must not collide');
      expect(
        web['fingerprint'],
        DVCrashFingerprint.of(errorType: 'StateError', frames: frames),
      );
      expect(
        web['override'],
        DVCrashFingerprint.of(
          errorType: 'StateError',
          frames: frames,
          override: 'checkout-helper',
        ),
      );
    },
    skip: hasNode
        ? false
        : 'node is not on PATH, so the dart2js output cannot be run here',
  );

  test('the VM fingerprint is the one reports already carry', () {
    // Pinned from before the arithmetic was made web-safe: groups a
    // deployment already has must keep their names.
    expect(
      DVCrashFingerprint.of(
        errorType: 'StateError',
        frames: DVCrashFrame.parse(
          '#0      CheckoutController.pay (package:shop/checkout/controller.dart:88:7)\n'
          '#1      PayButton.onPressed (package:shop/checkout/pay_button.dart:31:12)',
        ),
      ),
      'a86062ca51679c18',
    );
  });
}
