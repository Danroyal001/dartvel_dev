// dartvel.billing reaching the generated server.
//
// The provider is configuration: a project names it in pubspec.yaml and never
// builds one in code. So this generates a real backend the way `dartvel
// routes` does, starts it as a process, and asks a backend function what
// DV.Billing says -- never the generated text.
//
// The failures guarded are the quiet ones: a block the server never read (so
// checkout said "not set up" with every key in place), a server that refused
// to boot because a key was missing (it must start and say so at checkout),
// and an operator's switch to the backup provider that did nothing.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<void> main(List<String> arguments) async {
  Object? error;
  Object? answered;
  try {
    final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
    final HttpClient client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(
          'http://127.0.0.1:${handle.port}/api/billing_state'));
      final response = await request.close();
      answered = await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
    await handle.stop();
  } catch (e) {
    error = e;
  }
  stdout.writeln('PROBE ${jsonEncode(<String, Object?>{
    'error': error?.toString(),
    'answered': answered,
  })}');
  exit(0);
}
''';

void main() {
  late Directory project;
  late String packages;

  Future<ProcessResult> generate(Directory root) {
    final String cliPackage = p.join(packages, 'dartvel_cli');
    return Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
        p.join(cliPackage, 'bin', 'routes.dart'),
      ],
      workingDirectory: root.path,
    );
  }

  Directory scaffold(String billing) {
    final Directory root = Directory.systemTemp.createTempSync('dv_billing_');
    void write(String relative, String content) {
      final File file = File(p.join(root.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: billing_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
$billing
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    // The backend function builds no provider: it asks DV.Billing.
    write('lib/backend/functions/billing_state.get.dart', '''
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';

@DVBackendFunction()
Future<String> _billingState() async => DV.Billing.providerName == null
    ? 'none'
    : '\${DV.Billing.providerName!.name} \${DV.Billing.isSetUp} '
        '\${DV.Billing.confirmsOnReturn} \${DV.Billing.successUrl}';
''');
    write('bin/probe.dart', _probe);
    return root;
  }

  setUpAll(() async {
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    packages = p.dirname(
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
    );
    project = scaffold('''
  billing:
    provider: flutterwave
    successUrl: https://shop.example/payments/return
    cancelUrl: https://shop.example/cart
''');
    final ProcessResult generated = await generate(project);
    if (generated.exitCode != 0) {
      throw StateError(
        'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}',
      );
    }
    final ProcessResult resolved = await Process.run(
      Platform.resolvedExecutable,
      <String>['pub', 'get'],
      workingDirectory: project.path,
    );
    if (resolved.exitCode != 0) {
      throw StateError('dart pub get failed:\n${resolved.stderr}');
    }
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Future<String> ask(Map<String, String> environment) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: <String, String>{
        for (final String key in <String>['PATH', 'HOME', 'PUB_CACHE', 'TMPDIR'])
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
        ...environment,
      },
    ).timeout(const Duration(minutes: 3));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    final Map<String, Object?> r =
        jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
    expect(r['error'], isNull);
    // A backend function returning a String answers with the text itself.
    return '${r['answered']}';
  }

  test('with no keys the server starts, and billing is declared but not set up',
      () async {
    expect(await ask(const <String, String>{}),
        'flutterwave false true https://shop.example/payments/return');
  });

  test('with the keys in the environment it is set up', () async {
    expect(
        await ask(const <String, String>{
          'FLUTTERWAVE_SECRET_KEY': 'FLWSECK_TEST-probe-X',
          'FLUTTERWAVE_WEBHOOK_HASH': 'probe-hash',
        }),
        'flutterwave true true https://shop.example/payments/return');
  });

  test('DARTVEL_BILLING_PROVIDER and DARTVEL_BILLING_SITE_URL switch without a '
      'rebuild', () async {
    expect(
        await ask(const <String, String>{
          'DARTVEL_BILLING_PROVIDER': 'paystack',
          'PAYSTACK_SECRET_KEY': 'sk_test_probe_value',
          'DARTVEL_BILLING_SITE_URL': 'https://localhost:18443',
        }),
        'paystack true true https://localhost:18443/payments/return');
  });

  test('a block the reader refuses fails the build, naming the key', () async {
    final Directory broken = scaffold('''
  billing:
    provider: flutterwave
    apiKey: FLWSECK_TEST-pasted-key-X
    successUrl: https://shop.example/payments/return
    cancelUrl: https://shop.example/cart
''');
    try {
      final ProcessResult generated = await generate(broken);
      expect(generated.exitCode, isNot(0));
      expect('${generated.stdout}${generated.stderr}',
          allOf(contains('DV-BILLING-001'), contains('dartvel.billing.apiKey')));
    } finally {
      broken.deleteSync(recursive: true);
    }
  });
}
