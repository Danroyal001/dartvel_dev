// `dartvel.timers` reaches the app: the generated runtime installs DV.Timers
// before the first frame, and an Android build gets the broadcast receiver
// that rings a timer from the operating system. A project that does not ask
// gets none of it.
import 'dart:io';

import 'package:dartvel_cli/src/build/android_timers.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> _applicationFor(Directory root, Map<String, Object?> dartvel) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'kitchen_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'Kitchen',
    seoTitle: 'Kitchen',
    seoDesc: 'Kitchen',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: YamlMap.wrap(dartvel),
  );
  return File(p.join(root.path, 'lib', 'dartvel_client', 'application.g.dart')).readAsStringSync();
}

Directory _project() {
  final Directory root = Directory.systemTemp.createTempSync('dartvel_timers_');
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.dart')).writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage() Widget _index() => DVText("Home");
''');
  return root;
}

String _createApp(String out) {
  final int start = out.indexOf('Widget createDartvelApp(');
  return out.substring(start, out.indexOf('\n}\n', start));
}

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:label="Kitchen" android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true"/>
    </application>
</manifest>
''';

void main() {
  group('the generated runtime', () {
    test('off by default: no DV.Timers install', () async {
      final Directory root = _project();
      addTearDown(() => root.deleteSync(recursive: true));
      expect(_createApp(await _applicationFor(root, <String, Object?>{})), isNot(contains('DVTimers')));
    });

    test('on: DV.Timers installed before the first frame, under the app\'s name', () async {
      final Directory root = _project();
      addTearDown(() => root.deleteSync(recursive: true));
      final String app = _createApp(await _applicationFor(root, <String, Object?>{'timers': true}));
      expect(app, contains("DVTimers.install(app: 'kitchen_app');"));
      expect(app.indexOf('DVTimers.install'), lessThan(app.indexOf('return ')));
    });
  });

  group('dartvel.timers', () {
    test('reads true, and nothing else, as on', () {
      expect(dvTimersEnabled(<Object?, Object?>{'timers': true}), isTrue);
      expect(dvTimersEnabled(<Object?, Object?>{}), isFalse);
      expect(dvTimersEnabled(<Object?, Object?>{'timers': 'yes'}), isFalse);
    });
  });

  group('the Android manifest', () {
    test('gains the receivers and the permissions to ring on time', () {
      final String out = dvAndroidTimerManifest(_manifest, enabled: true);
      expect(out, contains('android:name=".DartvelTimerReceiver"'));
      expect(out, contains('android:name=".DartvelTimerBootReceiver"'));
      expect(out, contains('android.permission.POST_NOTIFICATIONS'));
      expect(out, contains('android.permission.SCHEDULE_EXACT_ALARM'));
      expect(out, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
      expect(out, contains('android.intent.action.BOOT_COMPLETED'));
      // The receiver that rings and snoozes takes no broadcast from another
      // app; only the boot one is reachable, and all it does is re-arm.
      final RegExp ringing = RegExp(r'<receiver[^>]*DartvelTimerReceiver"[^>]*android:exported="false"');
      expect(ringing.hasMatch(out), isTrue);
    });

    test('writing it twice changes nothing the second time', () {
      final String once = dvAndroidTimerManifest(_manifest, enabled: true);
      expect(dvAndroidTimerManifest(once, enabled: true), once);
    });

    test('turning it off takes back exactly what it added', () {
      final String on = dvAndroidTimerManifest(_manifest, enabled: true);
      expect(dvAndroidTimerManifest(on, enabled: false), _manifest);
    });

    test('a permission the app already declares is not declared twice', () {
      final String withPost = _manifest.replaceFirst('<application',
          '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application');
      final String out = dvAndroidTimerManifest(withPost, enabled: true);
      expect('android.permission.POST_NOTIFICATIONS'.allMatches(out), hasLength(1));
      expect(dvAndroidTimerManifest(out, enabled: false), withPost);
    });
  });

  group('the receiver source', () {
    test('is in the app\'s package and handles every action the Dart side sends', () {
      final String source = dvAndroidTimerReceiverSource('com.example.kitchen');
      expect(source, startsWith('package com.example.kitchen\n'));
      expect(source, contains('Written by dartvel build (dartvel.timers)'));
      expect(source, contains('class DartvelTimerReceiver'));
      expect(source, contains('class DartvelTimerBootReceiver'));
      for (final String action in <String>[
        dvAndroidTimerSchedule,
        dvAndroidTimerCancel,
        'dev.dartvel.timer.FIRE',
        'dev.dartvel.timer.SNOOZE',
        'dev.dartvel.timer.DISMISS',
      ]) {
        expect(source, contains('"$action"'), reason: action);
      }
      // What the receiver did while the app was away, where the Dart side
      // reads it back.
      expect(source, contains('"$dvAndroidTimerEventsFile"'));
    });
  });
}
