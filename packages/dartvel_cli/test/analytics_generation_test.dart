// `dartvel.analytics` read at generation.
//
// A configuration value that is skipped is the silent failure here: the
// application believes it declared a tracking category, a default or an
// experiment category, the build succeeds, and the running app does
// something else. So every value that is not understood stops generation,
// before a file is written, naming the key.
import 'dart:io';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _validAnalytics = '''
  analytics:
    store: database
    sessionCap: 500
    flags: { category: product }
    consent:
      version: "2026-09-01"
      categories:
        essential: { required: true }
        product: { default: granted }
        marketing: { default: denied, tracking: true }
''';

Directory _project(String analytics) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_analytics_gen_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: analytics_probe
publish_to: none
environment:
  sdk: ^3.9.0
dartvel:
  prodBackendHost: https://example.com
$analytics''');
  final File page = File(p.join(dir.path, 'lib', 'pages', 'index.page.dart'));
  page.parent.createSync(recursive: true);
  page.writeAsStringSync('''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
''');
  return dir;
}

String _read(Directory project, String name) =>
    File(p.join(project.path, 'lib', 'dartvel_client', name))
        .readAsStringSync();

void main() {
  final List<Directory> made = <Directory>[];
  tearDownAll(() {
    for (final Directory d in made) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Directory project(String analytics) {
    final Directory d = _project(analytics);
    made.add(d);
    return d;
  }

  group('a declared analytics configuration', () {
    late Directory dir;
    setUpAll(() async {
      dir = project(_validAnalytics);
      await routes.generate(root_: dir.path);
    });

    test('is generated as the settings the runtime starts from', () {
      final String generated = _read(dir, 'analytics.g.dart');
      expect(generated, contains("version: '2026-09-01'"));
      expect(generated, contains("DVConsentCategory('marketing')"));
      expect(generated, contains('tracking: true'));
      expect(generated, contains('flagExposureCategory: ConsentCategories.product'));
      expect(generated, contains('sessionCap: 500'));
      // Only dartvel_core: the generated server imports this file too, and
      // a Flutter import would compile Flutter into a process with no
      // dart:ui.
      expect(
        RegExp(r"^import '([^']+)'", multiLine: true)
            .allMatches(generated)
            .map((RegExpMatch m) => m.group(1))
            .toSet(),
        <String>{'dart:async', 'package:dartvel_core/dartvel.dart'},
      );
    });

    test('is exported and started by the client runtime', () {
      expect(_read(dir, 'dartvel_client.dart'),
          contains("export 'analytics.g.dart';"));
      final String runtime = _read(dir, 'dartvel_runtime.dart');
      expect(
          runtime,
          contains("configureDartvelAnalytics(database: () => "
              "dvLocalAnalyticsDatabase('analytics_probe', "
              'androidStateDirectory: DVDeviceRuntime.stateDirectory))'));
      // After the platform bindings: the database is opened as soon as the
      // runtime starts, and on Android the directory it goes in is the files
      // directory the bindings find. Before them it is null, the store falls
      // back to memory, and consent is asked again every launch.
      expect(runtime.indexOf('configureDartvelAnalytics('),
          greaterThan(runtime.indexOf('registerPlatformBindings();')));
      // And after the flags are declared, so the exposure sink it connects
      // is for flags the runtime knows.
      expect(runtime.indexOf('configureDartvelAnalytics('),
          greaterThan(runtime.indexOf('registerDartvelFlags();')));
    });

    test('is started by the generated server, with DV.Privacy', () {
      final String server = File(
              p.join(dir.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
          .readAsStringSync();
      expect(server, contains('configureDartvelBackendPrivacy('));
      expect(server, contains('configureDartvelAnalytics('));
    });
  });

  test('a project that declares no analytics starts nothing', () async {
    final Directory dir = project('');
    await routes.generate(root_: dir.path);
    final String generated = _read(dir, 'analytics.g.dart');
    expect(generated, contains('const DVAnalyticsSettings? dartvelAnalyticsSettings = null;'));
    expect(generated, isNot(contains('ConsentCategories')));
  });

  group('a value the generator does not understand stops the build', () {
    final Map<String, (String, String)> cases = <String, (String, String)>{
      'a misspelt analytics key': (
        _validAnalytics.replaceFirst('consent:', 'consnet:'),
        'consnet',
      ),
      'a misspelt category key': (
        _validAnalytics.replaceFirst('tracking: true', 'tracknig: true'),
        'tracknig',
      ),
      'a default that is not granted or denied': (
        _validAnalytics.replaceFirst('default: granted', 'default: grant'),
        'must be granted or denied',
      ),
      'a quoted boolean': (
        _validAnalytics.replaceFirst('required: true', 'required: "yes"'),
        'essential.required',
      ),
      'a store Dartvel does not have': (
        _validAnalytics.replaceFirst('store: database', 'store: clickhouse'),
        'clickhouse',
      ),
      'a flag category nobody declared': (
        _validAnalytics.replaceFirst(
            'flags: { category: product }', 'flags: { category: experiments }'),
        'experiments',
      ),
      'a missing version': (
        _validAnalytics.replaceFirst('version: "2026-09-01"', ''),
        'version',
      ),
      'a category name that is not a Dart name': (
        // marketing rather than product: flags names product, and renaming
        // it would be refused for that first.
        _validAnalytics.replaceFirst('marketing: {', 'marketing-email: {'),
        'marketing-email',
      ),
    };

    for (final MapEntry<String, (String, String)> c in cases.entries) {
      test(c.key, () async {
        final Directory dir = project(c.value.$1);
        await expectLater(
          routes.generate(root_: dir.path),
          throwsA(isA<StateError>().having((StateError e) => e.message,
              'message', allOf(contains('dartvel.analytics'), contains(c.value.$2)))),
        );
        expect(
            Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
            isFalse,
            reason: 'a build that fails must not leave half a client behind');
      });
    }
  });
}
