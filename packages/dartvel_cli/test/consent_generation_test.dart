// How a generated application asks for consent.
//
// Two silent failures belong to the build rather than the widgets. A
// declared category with no way to ask on a platform the application builds
// for is denied there for ever and nobody knows why (DV-ANALYTICS-002): on
// iOS a tracking category is asked through App Tracking Transparency, and the
// system will not show that prompt -- it terminates the app -- without a
// usage description in Info.plist. And a banner an application has to
// remember to place is a banner nobody sees, which leaves every
// default-denied category denied, so the generated routes carry it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _tracking = '''
  analytics:
    consent:
      version: "2026-09-01"
      categories:
        product: { default: denied }
        marketing: { default: denied, tracking: true }
''';

const String _notTracking = '''
  analytics:
    consent:
      version: "2026-09-01"
      categories:
        product: { default: denied }
''';

const String _plist = r'''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>probe</string>
$extra</dict>
</plist>
''';

Directory _project(String analytics, {String? infoPlist}) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_consent_gen_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: consent_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  prodBackendHost: https://example.com
$analytics''');
  File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
  if (infoPlist != null) {
    File(p.join(dir.path, 'ios', 'Runner', 'Info.plist'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(infoPlist);
  }
  return dir;
}

void main() {
  final List<Directory> made = <Directory>[];
  tearDownAll(() {
    for (final Directory d in made) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });
  Directory project(String analytics, {String? infoPlist}) {
    final Directory d = _project(analytics, infoPlist: infoPlist);
    made.add(d);
    return d;
  }

  group('DV-ANALYTICS-002 on iOS', () {
    test('a tracking category with no usage description stops the build',
        () async {
      final Directory dir =
          project(_tracking, infoPlist: _plist.replaceFirst(r'$extra', ''));
      await expectLater(
        routes.generate(root_: dir.path),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(contains('DV-ANALYTICS-002'), contains('marketing'),
              contains('NSUserTrackingUsageDescription')),
        )),
      );
      expect(Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
          isFalse);
    });

    test('with the usage description the build goes ahead', () async {
      final Directory dir = project(_tracking,
          infoPlist: _plist.replaceFirst(r'$extra',
              '\t<key>NSUserTrackingUsageDescription</key>\n\t<string>Ads</string>\n'));
      await routes.generate(root_: dir.path);
      expect(
          File(p.join(dir.path, 'lib', 'dartvel_client', 'analytics.g.dart'))
              .existsSync(),
          isTrue);
    });

    test('a key that is only mentioned in a comment does not count', () async {
      final Directory dir = project(_tracking,
          infoPlist: _plist.replaceFirst(r'$extra',
              '\t<!-- <key>NSUserTrackingUsageDescription</key> -->\n'));
      await expectLater(routes.generate(root_: dir.path), throwsStateError);
    });

    test('an application that does not build for iOS is not asked', () async {
      await routes.generate(root_: project(_tracking).path);
    });

    test('no tracking category, no prompt needed', () async {
      await routes.generate(
          root_: project(_notTracking,
                  infoPlist: _plist.replaceFirst(r'$extra', ''))
              .path);
    });
  });

  group('the banner', () {
    String router(Directory dir) =>
        File(p.join(dir.path, 'lib', 'dartvel_client', 'router.g.dart'))
            .readAsStringSync();

    test('is on every generated page when analytics is declared', () async {
      final Directory dir = project(_notTracking);
      await routes.generate(root_: dir.path);
      expect(router(dir),
          contains('DVPageLifecycleHost(child: DVConsentBanner(child: overridable))'));
    });

    test('is not on a page of an application with no analytics', () async {
      final Directory dir = project('');
      await routes.generate(root_: dir.path);
      expect(router(dir), isNot(contains('DVConsentBanner')));
    });
  });
}
