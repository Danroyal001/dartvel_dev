// The database an application's own device keeps consent in.
//
// Consent belongs to the install and is asked before anybody signs in, so it
// lives on the device. A store that did not survive a restart would not
// record a false grant -- it would ask again every launch, and a banner that
// never goes away is the kind of failure people click through without
// reading.
@TestOn('vm')
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('dv_analytics_local_');
    DVAnalyticsRuntime.resetForTest();
    DVPrivacyRuntime.resetForTest();
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final DVAnalyticsSettings settings =
      DVAnalyticsSettings.fromConfig(<String, Object?>{
    'consent': <String, Object?>{
      'version': '2026-09-01',
      'categories': <String, Object?>{
        'product': <String, Object?>{'default': 'denied'},
      },
    },
  });

  test('a choice made in one launch is in force in the next', () async {
    final DVAnalyticsRuntime first = DVAnalyticsRuntime.start(
      settings: settings,
      database: () => dvLocalAnalyticsDatabase('probe', directory: dir.path),
    );
    final DVConsent before = await first.consent;
    expect(before.needsPrompt, isTrue);
    expect(
        await before.record(
            <DVConsentCategory, bool>{const DVConsentCategory('product'): true}),
        isTrue);

    DVAnalyticsRuntime.resetForTest();
    final DVAnalyticsRuntime second = DVAnalyticsRuntime.start(
      settings: settings,
      database: () => dvLocalAnalyticsDatabase('probe', directory: dir.path),
    );
    final DVConsent after = await second.consent;
    expect(after.needsPrompt, isFalse);
    expect(after.installId, before.installId);
    expect(after.isGranted(const DVConsentCategory('product')), isTrue);
  });

  test('each application has its own file', () async {
    await dvLocalAnalyticsDatabase('one', directory: dir.path);
    await dvLocalAnalyticsDatabase('two', directory: dir.path);
    expect(
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .where((String n) => n.endsWith('.sqlite'))
          .length,
      2,
    );
  });

  test('an application id that is not a plain name is refused', () {
    expect(() => dvLocalAnalyticsDatabase('../elsewhere', directory: dir.path),
        throwsArgumentError);
  });

  group('where a device keeps it', () {
    // The per-user data directory each platform keeps across restarts, the
    // same rules crash records follow. Never HOME on Android, which sets
    // none, and never the temporary directory, which the system clears: a
    // consent store that disappears asks the person again and again.
    String? at(String os, Map<String, String> environment,
            {String? androidStateDirectory}) =>
        dvAnalyticsDirectoryFor(
          appId: 'probe',
          os: os,
          environment: environment,
          androidStateDirectory: androidStateDirectory,
        );

    test('each platform\'s per-user data directory', () {
      expect(
        at('android', const <String, String>{},
            androidStateDirectory:
                '/data/user/0/com.example.probe/files/dartvel-device'),
        '/data/user/0/com.example.probe/files/dartvel-analytics',
      );
      expect(at('ios', const <String, String>{'HOME': '/var/mobile/App'}),
          '/var/mobile/App/Library/Application Support/probe/dartvel-analytics');
      expect(at('macos', const <String, String>{'HOME': '/Users/ada'}),
          '/Users/ada/Library/Application Support/probe/dartvel-analytics');
      expect(
          at('windows', const <String, String>{
            'LOCALAPPDATA': r'C:\Users\ada\AppData\Local',
          }),
          r'C:\Users\ada\AppData\Local\probe\dartvel-analytics');
      expect(at('linux', const <String, String>{'XDG_DATA_HOME': '/xdg'}),
          '/xdg/probe/dartvel-analytics');
      expect(at('linux', const <String, String>{'HOME': '/home/ada'}),
          '/home/ada/.local/share/probe/dartvel-analytics');
    });

    test('DARTVEL_ANALYTICS_DIR wins everywhere', () {
      expect(
        at('android', const <String, String>{'DARTVEL_ANALYTICS_DIR': '/mnt/a/'},
            androidStateDirectory: '/data/files/dartvel-device'),
        '/mnt/a',
      );
    });

    test('no usable directory is null, not a guess', () {
      expect(at('android', const <String, String>{}), isNull);
      expect(at('linux', const <String, String>{'HOME': '/'}), isNull);
      expect(at('windows', const <String, String>{}), isNull);
    });

    test('with no directory the database is kept in memory, writing nothing',
        () async {
      final DVDatabaseAdapter db = await dvLocalAnalyticsDatabase(
        'probe',
        os: 'android',
        environment: const <String, String>{},
      );
      expect(db, isA<MemoryDVDatabaseAdapter>());
    });

    test('under flutter test nothing is written to the developer\'s machine',
        () async {
      final DVDatabaseAdapter db = await dvLocalAnalyticsDatabase(
        'probe',
        os: 'linux',
        environment: <String, String>{
          'FLUTTER_TEST': 'true',
          'XDG_DATA_HOME': dir.path,
        },
      );
      expect(db, isA<MemoryDVDatabaseAdapter>());
      expect(dir.listSync(recursive: true), isEmpty);
    });

    test('otherwise it is a file in that directory', () async {
      await dvLocalAnalyticsDatabase(
        'probe',
        os: 'linux',
        environment: <String, String>{'XDG_DATA_HOME': dir.path},
      );
      expect(
        File('${dir.path}/probe/dartvel-analytics/probe.analytics.sqlite')
            .existsSync(),
        isTrue,
      );
    });
  });
}
