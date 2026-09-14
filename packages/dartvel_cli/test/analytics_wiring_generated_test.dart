// `dartvel.analytics` in a generated project, run.
//
// The generation tests read what is emitted; this generates a project the
// way `dartvel build` does, resolves it against the real packages, analyzes
// it, and runs a test inside it against the generated wiring. What it proves
// is behaviour: the policy the pubspec declares is the one the running
// pipeline enforces, an event tracked while the stored consent is still
// being read is judged against that stored choice, and the privacy walk the
// server configures carries the analytics adapters.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _page = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

/// An event declared the way the section declares one, naming its category
/// through the generated constants.
const String _event = '''
import '../dartvel_client/dartvel_client.dart';

class ProductViewed extends DVAnalyticsEvent {
  const ProductViewed();

  @override
  String get name => 'product_viewed';

  @override
  DVConsentCategory get category => ConsentCategories.product;
}
''';

const String _wiringTest = r'''
import 'dart:async';

import 'package:analytics_wiring_probe/dartvel_client/analytics.g.dart';
import 'package:analytics_wiring_probe/dartvel_client/privacy.g.dart';
import 'package:analytics_wiring_probe/events/product_viewed.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DVAnalyticsRuntime.resetForTest();
    DVPrivacyRuntime.resetForTest();
    DVFlags.resetForTest();
  });

  test('the running policy is the declared one', () {
    final DVConsentPolicy policy = dartvelAnalyticsSettings!.consent;
    expect(policy.version, '2026-09-01');
    expect(policy.declaration(ConsentCategories.product)!.defaultGranted, isTrue);
    expect(policy.declaration(ConsentCategories.marketing)!.tracking, isTrue);
    expect(dartvelAnalyticsSettings!.flagExposureCategory, ConsentCategories.product);
  });

  test('an early event waits for the stored consent', () async {
    final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
    configureDartvelAnalytics(database: () => db);
    final DVConsent consent = await DVAnalyticsRuntime.current.consent;
    expect(await consent.record(<DVConsentCategory, bool>{ConsentCategories.product: false}), isTrue);

    DVAnalyticsRuntime.resetForTest();
    final Completer<void> opened = Completer<void>();
    configureDartvelAnalytics(database: () async {
      await opened.future;
      return db;
    });
    final Future<DVTrackResult> early = DVAnalyticsRuntime.current.track(const ProductViewed());
    opened.complete();
    final DVTrackResult result = await early;
    expect(result.accepted, isFalse);
    expect(result.code, 'DV-ANALYTICS-001');
  });

  test('the server privacy walk carries the analytics adapters', () async {
    final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
    configureDartvelAnalytics(database: () => db);
    await DVAnalyticsRuntime.current.ready;
    expect(
      configureDartvelBackendPrivacy(
        database: db,
        environment: <String, String>{'DARTVEL_PRIVACY_KEY': List<String>.filled(32, 'ab').join()},
      ),
      isTrue,
    );
    expect(DVPrivacyRuntime.current.adapters.map((DVPrivacyAdapter a) => a.name),
        containsAll(<String>['analytics:events', 'analytics:consent']));
  });

  test('without the key the server configures no privacy walk', () {
    expect(
      configureDartvelBackendPrivacy(database: MemoryDVDatabaseAdapter(), environment: const <String, String>{}),
      isFalse,
    );
    expect(() => DVPrivacyRuntime.current, throwsStateError);
  });
}
''';

Future<String> _repoRoot() async {
  final Uri? lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'));
  if (lib == null) throw StateError('dartvel_cli did not resolve itself');
  return p.normalize(p.join(p.dirname(lib.toFilePath()), '..', '..', '..'));
}

void _write(String path, String contents) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  late Directory project;
  late ProcessResult analysis;
  late ProcessResult run;

  setUpAll(() async {
    final String root = await _repoRoot();
    project = await Directory.systemTemp.createTemp('dv_analytics_wiring_');
    _write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _page);
    _write(p.join(project.path, 'lib', 'events', 'product_viewed.dart'), _event);
    _write(p.join(project.path, 'test', 'analytics_wiring_test.dart'),
        _wiringTest);
    _write(p.join(project.path, 'pubspec.yaml'), '''
name: analytics_wiring_probe
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
dev_dependencies:
  flutter_test:
    sdk: flutter
dartvel:
  prodBackendHost: https://example.com
  analytics:
    flags: { category: product }
    consent:
      version: "2026-09-01"
      categories:
        essential: { required: true }
        product: { default: granted }
        marketing: { default: denied, tracking: true }
''');
    _write(p.join(project.path, 'pubspec_overrides.yaml'), '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
''');

    await routes.generate(root_: project.path);

    final ProcessResult resolved = await Process.run(
        'flutter', <String>['pub', 'get'],
        workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
    analysis = await Process.run('flutter', <String>['analyze', 'lib'],
        workingDirectory: project.path);
    run = await Process.run(
        'flutter', <String>['test', 'test/analytics_wiring_test.dart'],
        workingDirectory: project.path);
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  test('the generated client with analytics analyzes clean', () {
    final List<String> findings = const LineSplitter()
        .convert('${analysis.stdout}${analysis.stderr}')
        .where((String l) =>
            l.contains('error •') ||
            l.contains('warning •') ||
            (l.contains('info •') && l.contains('dartvel_client')))
        .where((String l) => !l.contains('.page.dart'))
        .toList();
    expect(findings, isEmpty, reason: findings.join('\n'));
  });

  test('the generated wiring behaves as declared when run', () {
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect('${run.stdout}', contains('All tests passed'));
  });
}
