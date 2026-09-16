// The files dartvel.deepLinks puts where each platform looks.
//
// The two verification documents under the web build's .well-known, the
// App Links intent filter in the Android manifest, the associated domains in
// the iOS entitlements, and the checks `dartvel doctor --target android,ios`
// makes against what is actually deployed.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/deep_link_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _fingerprint =
    '14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:8A:04:96:B2:3F:CF:44:E5';

final DVDeepLinks _links = DVDeepLinks.parse(<String, Object?>{
  'domains': <String>['example.com', 'www.example.com'],
  'android': <String, Object?>{
    'package': 'com.example.app',
    'fingerprints': <String>[_fingerprint],
  },
  'ios': <String, Object?>{'appId': 'ABCDE12345.com.example.app'},
  'exclude': <String>['/admin/**'],
})!;

const String _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="app">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
</manifest>
''';

const String _entitlements = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
''';

void main() {
  late Directory web;
  setUp(() async {
    web = await Directory.systemTemp.createTemp('dartvel_deep_links_');
  });
  tearDown(() => web.deleteSync(recursive: true));

  group('the web build', () {
    test('writes both documents under .well-known', () {
      final int written = dvWriteDeepLinkFiles(
        webDir: web.path,
        links: _links,
        routes: <String>['/', '/team/:member', '/admin/reports', '/account'],
        guarded: <String>{'/account'},
      );
      expect(written, 2);

      final Object? android = jsonDecode(
        File(
          p.join(web.path, '.well-known', 'assetlinks.json'),
        ).readAsStringSync(),
      );
      expect(
        (android! as List<Object?>).single,
        containsPair('target', containsPair('package_name', 'com.example.app')),
      );

      final Map<String, Object?> apple =
          jsonDecode(
                File(
                  p.join(web.path, '.well-known', 'apple-app-site-association'),
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(jsonEncode(apple), contains('"/team/*"'));
      expect(jsonEncode(apple), isNot(contains('/admin')));
      expect(jsonEncode(apple), isNot(contains('/account')));
    });

    test('nothing declared writes nothing, and removes an old file', () {
      Directory(p.join(web.path, '.well-known')).createSync();
      File(
        p.join(web.path, '.well-known', 'assetlinks.json'),
      ).writeAsStringSync('[]');
      expect(
        dvWriteDeepLinkFiles(
          webDir: web.path,
          links: null,
          routes: <String>['/'],
          guarded: const <String>{},
        ),
        0,
      );
      expect(
        File(p.join(web.path, '.well-known', 'assetlinks.json')).existsSync(),
        isFalse,
      );
    });
  });

  group('the Android manifest', () {
    test('gains a verified intent filter per domain, inside MainActivity', () {
      final String after = dvAndroidDeepLinkManifest(
        _manifest,
        _links,
        paths: <String>['/', '/team/*'],
      );
      final int activityEnd = after.indexOf('</activity>');
      final int filter = after.indexOf('android:autoVerify="true"');
      expect(filter, greaterThan(0));
      expect(filter, lessThan(activityEnd));
      expect(after, contains('android:host="example.com"'));
      expect(after, contains('android:host="www.example.com"'));
      expect(after, contains('android:scheme="https"'));
      expect(after, contains('android:pathPattern="/team/.*"'));
      expect(after, contains('android:path="/"'));
    });

    test('a second build replaces the block rather than adding another', () {
      final String once = dvAndroidDeepLinkManifest(
        _manifest,
        _links,
        paths: <String>['/'],
      );
      final String twice = dvAndroidDeepLinkManifest(
        once,
        _links,
        paths: <String>['/'],
      );
      expect(twice, once);
    });

    test('no deep links leaves the manifest as it was', () {
      final String once = dvAndroidDeepLinkManifest(
        _manifest,
        _links,
        paths: <String>['/'],
      );
      expect(
        dvAndroidDeepLinkManifest(once, null, paths: <String>[]),
        _manifest,
      );
    });
  });

  group('the iOS entitlements', () {
    test('name every domain as applinks:', () {
      final String after = dvIosAssociatedDomains(_entitlements, _links);
      expect(
        after,
        contains('<key>com.apple.developer.associated-domains</key>'),
      );
      expect(after, contains('<string>applinks:example.com</string>'));
      expect(after, contains('<string>applinks:www.example.com</string>'));
      expect(dvIosAssociatedDomains(after, _links), after);
      expect(dvIosAssociatedDomains(after, null), _entitlements);
    });
  });

  group('dartvel doctor --target android,ios', () {
    late HttpServer server;
    late String host;
    final Map<String, (int, String, String)> served =
        <String, (int, String, String)>{};

    setUp(() async {
      served.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      host = '127.0.0.1:${server.port}';
      server.listen((HttpRequest request) {
        final (int, String, String)? answer = served[request.uri.path];
        if (answer == null) {
          request.response.statusCode = 404;
        } else {
          request.response.statusCode = answer.$1;
          if (answer.$1 >= 300 && answer.$1 < 400) {
            request.response.headers.set('location', answer.$3);
          } else {
            request.response.headers.set('content-type', answer.$2);
            request.response.write(answer.$3);
          }
        }
        request.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    DVDeepLinks linksFor(String domain) => DVDeepLinks.parse(<String, Object?>{
      'domains': <String>[domain],
      'android': <String, Object?>{
        'package': 'com.example.app',
        'fingerprints': <String>[_fingerprint],
      },
      'ios': <String, Object?>{'appId': 'ABCDE12345.com.example.app'},
    })!;

    test('files that are right pass', () async {
      final DVDeepLinks links = linksFor('example.com');
      served['/.well-known/assetlinks.json'] = (
        200,
        'application/json',
        links.assetLinks()!,
      );
      served['/.well-known/apple-app-site-association'] = (
        200,
        'application/json',
        links.appleAppSiteAssociation(<String>['/', '/team/*'])!,
      );
      final List<String> findings = await dvCheckDeepLinks(
        links: links,
        targets: <String>{'android', 'ios'},
        routes: <String>['/', '/team/:member'],
        guarded: const <String>{},
        signingFingerprint: _fingerprint,
        origin: (String domain) => Uri.parse('http://$host'),
      );
      expect(findings, isEmpty);
    });

    test('DV-LINKS-002: missing, redirected, or not JSON', () async {
      final DVDeepLinks links = linksFor('example.com');
      served['/.well-known/assetlinks.json'] = (
        301,
        '',
        'http://$host/elsewhere',
      );
      served['/.well-known/apple-app-site-association'] = (
        200,
        'application/octet-stream',
        links.appleAppSiteAssociation(<String>['/'])!,
      );
      final List<String> findings = await dvCheckDeepLinks(
        links: links,
        targets: <String>{'android', 'ios'},
        routes: <String>['/'],
        guarded: const <String>{},
        origin: (String domain) => Uri.parse('http://$host'),
      );
      expect(
        findings.where((String f) => f.contains('DV-LINKS-002')),
        hasLength(2),
      );
      expect(findings.join('\n'), contains('redirect'));
      expect(findings.join('\n'), contains('application/octet-stream'));
    });

    test('DV-LINKS-003: the served fingerprint is not the signing one', () async {
      final DVDeepLinks links = linksFor('example.com');
      served['/.well-known/assetlinks.json'] = (
        200,
        'application/json',
        links.assetLinks()!,
      );
      final List<String> findings = await dvCheckDeepLinks(
        links: links,
        targets: <String>{'android'},
        routes: <String>['/'],
        guarded: const <String>{},
        signingFingerprint:
            '00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00',
        origin: (String domain) => Uri.parse('http://$host'),
      );
      expect(findings.single, contains('DV-LINKS-003'));
    });

    test('DV-LINKS-004: a route the served patterns do not cover', () async {
      final DVDeepLinks links = linksFor('example.com');
      served['/.well-known/apple-app-site-association'] = (
        200,
        'application/json',
        links.appleAppSiteAssociation(<String>['/'])!,
      );
      final List<String> findings = await dvCheckDeepLinks(
        links: links,
        targets: <String>{'ios'},
        routes: <String>['/', '/team/:member'],
        guarded: const <String>{},
        origin: (String domain) => Uri.parse('http://$host'),
      );
      expect(findings.single, contains('DV-LINKS-004'));
      expect(findings.single, contains('/team/:member'));
    });
  });
}
