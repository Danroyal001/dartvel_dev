// Crash reporting in a generated client, across two launches.
//
// The crash runtime existed and nothing installed it, so a real application
// recorded nothing. This generates a client the way `dartvel routes` does,
// resolves it against the real packages, and runs two `flutter test`
// processes against one crash directory: the first has an error, the second
// is the next launch. Asserting on what each process did, never on the
// generated text, is the only way to see the silent failures:
//
//  * the application's own FlutterError.onError replaced;
//  * one error that reaches FlutterError.onError and PlatformDispatcher
//    recorded twice;
//  * a report that is not on disk when the handler returns;
//  * the report never sent by the next launch;
//  * an install id that changes on every launch, which turns crash-free
//    users into crash-free launches.
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probeHeader = r'''
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:crash_probe/dartvel_client/dartvel_client.dart' hide Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final Directory crashes = Directory(Platform.environment['DARTVEL_CRASH_DIR']!);

List<Map<String, Object?>> records() => <Map<String, Object?>>[
      if (crashes.existsSync())
        for (final FileSystemEntity f in crashes.listSync())
          if (f is File && f.path.endsWith('.crash'))
            jsonDecode(f.readAsStringSync()) as Map<String, Object?>,
    ];
''';

const String _firstLaunch = '''
$_probeHeader
void main() {
  test('first launch', () {
    final FlutterExceptionHandler? testHandler = FlutterError.onError;
    final ErrorCallback? testDispatcher = PlatformDispatcher.instance.onError;
    final List<FlutterErrorDetails> app = <FlutterErrorDetails>[];
    void appHandler(FlutterErrorDetails d) => app.add(d);
    FlutterError.onError = appHandler;

    final Map<String, Object?> out = <String, Object?>{};
    out['installedUnderTestByDefault'] =
        installDartvelCrashReporting() != null;
    final DVCrashInstallation installation =
        installDartvelCrashReporting(evenUnderTest: true)!;

    final StateError error = StateError('first launch');
    final StackTrace stack = StackTrace.current;
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    out['recordsWhenHandlerReturned'] = records().length;
    out['appHandlerCalls'] = app.length;
    PlatformDispatcher.instance.onError!(error, stack);
    out['recordsAfterSecondHook'] = records().length;
    final Map<String, Object?> context =
        records().single['context']! as Map<String, Object?>;
    out['release'] = context['release'];
    out['installId'] = context['installId'];

    installation.uninstall();
    out['appHandlerRestored'] = identical(FlutterError.onError, appHandler) ||
        FlutterError.onError == appHandler;
    FlutterError.onError = testHandler;
    PlatformDispatcher.instance.onError = testDispatcher;
    // ignore: avoid_print
    print('PROBE \${jsonEncode(out)}');
  });
}
''';

const String _nextLaunch = '''
$_probeHeader
void main() {
  test('next launch', () async {
    final FlutterExceptionHandler? testHandler = FlutterError.onError;
    final ErrorCallback? testDispatcher = PlatformDispatcher.instance.onError;
    final DVMemoryCrashSink sink = DVMemoryCrashSink();

    FlutterError.onError = (FlutterErrorDetails d) {};
    final DVCrashInstallation installation =
        installDartvelCrashReporting(sink: sink, evenUnderTest: true)!;
    final int sent = await installation.recovered;

    final Map<String, Object?> out = <String, Object?>{
      'sent': sent,
      'messages': <String>[for (final r in sink.received) r.message],
      'installIds': <String>[for (final r in sink.received) r.context.installId],
      'recordsLeft': records().length,
    };
    // The reports sent above were written by the first launch and carry its
    // id whatever this launch does. What this launch's own install id is only
    // shows on a report this launch writes.
    FlutterError.reportError(FlutterErrorDetails(
      exception: StateError('next launch'),
      stack: StackTrace.current,
    ));
    out['installIdNow'] = (records().single['context']!
        as Map<String, Object?>)['installId'];
    installation.uninstall();
    FlutterError.onError = testHandler;
    PlatformDispatcher.instance.onError = testDispatcher;
    // ignore: avoid_print
    print('PROBE \${jsonEncode(out)}');
  });
}
''';

/// A launch under the project's dartvel.crashes, in a crash directory of its
/// own: what the generated runtime does with the declaration, and with the
/// flags the build generated.
const String _configured = '''
$_probeHeader
void main() {
  test('configured', () async {
    final FlutterExceptionHandler? testHandler = FlutterError.onError;
    final ErrorCallback? testDispatcher = PlatformDispatcher.instance.onError;
    FlutterError.onError = (FlutterErrorDetails d) {};
    final Map<String, Object?> out = <String, Object?>{};

    registerDartvelFlags();
    DVFlags.setRules(const DVFlagRules(
      rulesVersion: 1,
      flags: <String, List<DVFlagRule>>{
        'newCheckout': <DVFlagRule>[DVFlagRule(value: true)],
      },
    ));
    const DVConsentCategory category = DVConsentCategory('crash_identity');
    final DVConsent consent = DVConsent(
      policy: DVConsentPolicy(
        version: '1',
        categories: const <DVConsentDeclaration>[DVConsentDeclaration(category)],
      ),
      database: MemoryDVDatabaseAdapter(),
      installId: 'probe',
    );
    await consent.ensureSchema();
    await consent.record(<DVConsentCategory, bool>{category: true});

    final DVCrashInstallation installation =
        installDartvelCrashReporting(evenUnderTest: true)!;
    DV.Crashes.identify('user-42', consent: consent);

    out['nonFatalKept'] = DV.Crashes.record(StateError('caught')) != null;
    for (final String message in <String>['one', 'two', 'three']) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError(message),
        stack: StackTrace.current,
      ));
    }
    final List<Map<String, Object?>> written = records();
    out['written'] = written.length;
    out['userId'] =
        (written.first['context']! as Map<String, Object?>)['userId'];
    out['flags'] = written.first['flags'];

    installation.uninstall();
    FlutterError.onError = testHandler;
    PlatformDispatcher.instance.onError = testDispatcher;
    // ignore: avoid_print
    print('PROBE \${jsonEncode(out)}');
  });
}
''';

const String _flags = '''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
@pragma('vm:entry-point')
abstract class _Flags {
  @DVFlag(owner: 'payments', expires: '2099-12-01')
  static const bool newCheckout = false;

  @pragma('vm:entry-point')
  static List<Object?> get declared => <Object?>[newCheckout];
}
''';

const String _indexPage = '''
import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => const DVText('Home');
''';

Future<String> repoRoot() async {
  final Uri? lib = await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/dartvel_cli.dart'),
  );
  return p.normalize(p.join(p.dirname(lib!.toFilePath()), '..', '..', '..'));
}

void write(String path, String contents) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  late Directory project;
  late String crashDir;

  setUpAll(() async {
    final String root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_crash_client_');
    crashDir = p.join(project.path, 'crash-records');
    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _indexPage);
    write(p.join(project.path, 'test', 'first_launch_test.dart'), _firstLaunch);
    write(p.join(project.path, 'test', 'next_launch_test.dart'), _nextLaunch);
    write(p.join(project.path, 'test', 'configured_test.dart'), _configured);
    write(p.join(project.path, 'lib', 'flags', 'flags.dart'), _flags);
    write(p.join(project.path, 'pubspec.yaml'), '''
name: crash_probe
version: 2.3.4+5
publish_to: none
environment:
  sdk: ^3.13.0
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
  crashes:
    nonFatalSampleRate: 0
    fullReportsPerRelease: 2
    identity:
      consent: crash_identity
''');
    write(p.join(project.path, 'pubspec_overrides.yaml'), '''
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
      'flutter',
      <String>['pub', 'get'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Future<Map<String, Object?>> launch(String testFile, {String? directory}) async {
    final ProcessResult result = await Process.run(
      'flutter',
      <String>['test', testFile],
      workingDirectory: project.path,
      environment: <String, String>{'DARTVEL_CRASH_DIR': directory ?? crashDir},
    ).timeout(const Duration(minutes: 8));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .map((String l) => l.trim())
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('$testFile did not run (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  test('an error is recorded on disk, once, through the chain, and sent by '
      'the next launch under the same install id', () async {
    final Map<String, Object?> first = await launch(
      'test/first_launch_test.dart',
    );

    // Under flutter test the framework owns the hooks, so the runtime leaves
    // them alone unless asked; otherwise every widget test of an application
    // would write crash records into the developer's data directory.
    expect(first['installedUnderTestByDefault'], isFalse);
    expect(first['recordsWhenHandlerReturned'], 1);
    expect(first['appHandlerCalls'], 1);
    expect(first['recordsAfterSecondHook'], 1);
    expect(first['appHandlerRestored'], isTrue);
    expect(first['release'], '2.3.4+5');
    expect(first['installId'], matches(RegExp(r'^[0-9a-f]{32}$')));

    final Map<String, Object?> next = await launch(
      'test/next_launch_test.dart',
    );
    expect(next['sent'], 1);
    expect(next['messages'], <String>['Bad state: first launch']);
    expect(next['installIds'], <Object?>[first['installId']]);
    expect(next['recordsLeft'], 0);
    // One install, two launches, one id.
    expect(next['installIdNow'], first['installId']);
  });

  test('dartvel.crashes reaches the generated runtime: the sample rate, the '
      'limit, the identity category, and the generated flags', () async {
    final Map<String, Object?> r = await launch(
      'test/configured_test.dart',
      directory: p.join(project.path, 'configured-records'),
    );

    // nonFatalSampleRate: 0 drops every non-fatal.
    expect(r['nonFatalKept'], isFalse);
    // fullReportsPerRelease: 2 writes two of three crashes and counts the
    // third.
    expect(r['written'], 2);
    // identity.consent names the category identify binds to; it is granted.
    expect(r['userId'], 'user-42');
    // The flags the build generated, as the rules answer them.
    expect((r['flags']! as Map<String, Object?>)['newCheckout'], isTrue);
  });

  test('configureDartvelRuntime installs crash reporting', () {
    // The one text check here: the call itself. Everything it does is proven
    // by running it above; that configure makes it cannot be run under
    // flutter test without taking the single-instance lock and the
    // platform bindings with it.
    final String runtime = File(
      p.join(project.path, 'lib', 'dartvel_client', 'dartvel_runtime.dart'),
    ).readAsStringSync();
    final int configure = runtime.indexOf('void configureDartvelRuntime(');
    final int end = runtime.indexOf('\n}\n', configure);
    expect(
      runtime.substring(configure, end),
      contains('installDartvelCrashReporting();'),
    );
  });
}
