// A third-party request through the generated backend's own lifecycle.
//
// DVApiKeys.check and DVOAuthProvider.authenticate existed, and no generated
// route asked either: a key presented to a real backend was a header nobody
// read, so a route guarded by a policy action was guarded only by whatever
// the application's own auth made of the request. This generates a real
// backend with dartvel.platformApi declared, starts it, and calls it over
// HTTP with real keys -- asserting on the statuses it answered and on what the
// process printed, never on the generated text.
//
// The silent failures:
//  * a key accepted on a request resolved to another tenant, which reads the
//    wrong customer's data with a valid credential;
//  * a call outside the key's scopes allowed because the application's policy
//    said yes -- the scope check skipped on a generated route;
//  * a key reaching a route that declares no policy action, where no scope
//    can have been checked;
//  * a refusal that says why (revoked, wrong tenant, unknown id), which lets
//    a caller probe which keys exist;
//  * a key secret in a log line or a response body;
//  * a rate plan that never throttles.
@Timeout(Duration(minutes: 12))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:lifecycle_probe/dartvel_client/platform_api.g.dart' as api;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<Map<String, Object?>> call(
  int port,
  String method,
  String path, {
  String? bearer,
  String tenant = 'acme',
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-tenant', tenant);
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (method == 'POST') {
      request.headers.contentType = ContentType.json;
      request.write('{}');
    }
    final HttpClientResponse response = await request.close();
    return <String, Object?>{
      'status': response.statusCode,
      'body': await response.transform(utf8.decoder).join(),
      'www': response.headers.value('www-authenticate'),
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
  const DVDatabase().configure(db);
  // The application's own policy answers yes to everything, so every refusal
  // below is the platform API's and none is the application's.
  bool allow = true;
  // Who the policy was asked about: the principal is the policy context.
  final List<String?> seen = <String?>[];
  DVBackendPolicy.decide = (String policy, String path) async {
    seen.add(DVApiPrincipal.current?.subject);
    return allow;
  };

  final DVApiKeys keys = DVApiKeys(
    database: db,
    scopes: api.dartvelPlatformApi!.scopes,
  );
  await keys.ensureSchema();
  final DVIssuedApiKey read =
      await keys.issue(tenant: 'acme', scopes: <String>['orders:read']);
  final DVIssuedApiKey write =
      await keys.issue(tenant: 'acme', scopes: <String>['orders:write']);
  final DVIssuedApiKey limited = await keys.issue(
      tenant: 'acme', scopes: <String>['orders:read'], ratePlan: 'tiny');
  final DVIssuedApiKey revoked =
      await keys.issue(tenant: 'acme', scopes: <String>['orders:read']);
  await keys.revoke(revoked.key.id);

  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{
    'secrets': <String>[read.secret, write.secret, limited.secret, revoked.secret],
  };
  try {
    out['anonymous'] = await call(port, 'GET', '/api/orders');
    out['appBearer'] =
        await call(port, 'GET', '/api/orders', bearer: 'app-session-token');
    out['read'] = await call(port, 'GET', '/api/orders', bearer: read.secret);
    out['otherTenant'] = await call(port, 'GET', '/api/orders',
        bearer: read.secret, tenant: 'globex');
    out['unknown'] = await call(port, 'GET', '/api/orders',
        bearer: 'dvk_0123456789abcdef_${'A' * 43}');
    out['revoked'] =
        await call(port, 'GET', '/api/orders', bearer: revoked.secret);
    out['outsideScope'] =
        await call(port, 'POST', '/api/orders', bearer: read.secret);
    out['write'] =
        await call(port, 'POST', '/api/orders', bearer: write.secret);
    out['noPolicy'] = await call(port, 'GET', '/api/open', bearer: read.secret);
    out['noPolicyAnonymous'] = await call(port, 'GET', '/api/open');
    out['oauthDisabled'] = await call(port, 'GET', '/api/orders',
        bearer: 'dvat_${'B' * 43}');
    allow = false;
    out['policyDenies'] =
        await call(port, 'POST', '/api/orders', bearer: write.secret);
    allow = true;
    out['limited'] = <Object?>[
      for (int i = 0; i < 3; i++)
        await call(port, 'GET', '/api/orders', bearer: limited.secret),
    ];
  } finally {
    await handle.stop();
  }
  out['seen'] = seen;
  out['writeKey'] = write.key.id;
  stdout.writeln('PROBE ${jsonEncode(out)}');
  exit(0);
}
''';

Future<String> packagesDirectory() async {
  final Uri cli = (await Isolate.resolvePackageUri(
    Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
  ))!;
  return p.dirname(
    p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))),
  );
}

void main() {
  late Directory project;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_platform_lifecycle_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: lifecycle_probe
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
  tenancy:
    source: header
  platformApi:
    scopes:
      orders:read: [Order.view]
      orders:write: [Order.create]
    ratePlans:
      tiny: { maxRequests: 2, window: 1h }
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    write('lib/policies/order_policy.dart', '''
import 'package:dartvel_core/dartvel.dart';

class Order {
  const Order();
}

@DVPolicy(Order)
class OrderPolicy {
  bool view(Object? user, Order order) => true;
  bool create(Object? user, Order order) => true;
}
''');
    // The tenant is read in a helper of the function's own file: a function
    // body is lowered into the generated backend and reaches names of its
    // file through that file's import prefix, not through its imports.
    write('lib/backend/functions/orders.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: 'Order.view')
Future<Map<String, Object?>> _listOrders() async => <String, Object?>{
      'tenant': currentTenantName(),
    };

String currentTenantName() => const DVTenants().currentTenant;
''');
    write('lib/backend/functions/orders.post.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: 'Order.create')
Future<String> _createOrder() async => 'created';
''');
    write('lib/backend/functions/open.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _open() async => 'open';
''');
    write('bin/probe.dart', _probe);

    final String cliPackage = p.join(packages, 'dartvel_cli');
    final ProcessResult generated = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        '--packages=${p.join(cliPackage, '.dart_tool', 'package_config.json')}',
        p.join(cliPackage, 'bin', 'routes.dart'),
      ],
      workingDirectory: project.path,
    );
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

  late Map<String, Object?> r;
  late String output;

  setUpAll(() async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 4));
    output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    r = jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  });

  Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
  int status(String key) => at(key)['status']! as int;

  test('a key with the scope reaches its route, on its own tenant', () {
    expect(status('read'), 200);
    expect(jsonDecode(at('read')['body']! as String), <String, Object?>{
      'tenant': 'acme',
    });
  });

  test('a key presented for another tenant does not authenticate', () {
    expect(status('otherTenant'), 401);
  });

  test('every credential refusal is the same answer', () {
    // Wrong tenant, unknown id and revoked each answer exactly what the
    // others do, so none of them tells a caller anything.
    for (final String key in <String>['otherTenant', 'unknown', 'revoked']) {
      expect(status(key), 401, reason: key);
      expect(at(key)['body'], at('unknown')['body'], reason: key);
      expect(at(key)['www'], at('unknown')['www'], reason: key);
    }
    expect('${at('unknown')['www']}', startsWith('Bearer'));
  });

  test('a call outside the key\'s scopes is refused although the policy '
      'allows it', () {
    expect(status('outsideScope'), 403);
    expect(status('write'), 200);
    expect(at('write')['body'], 'created');
  });

  test('inside its scopes the application\'s policy still decides', () {
    expect(status('policyDenies'), 403);
  });

  test('the policy is asked with the key as the caller', () {
    // The principal is the policy context: the application's decision sees
    // which key is calling, and a request without one is nobody.
    final List<Object?> seen = r['seen']! as List<Object?>;
    expect(seen, contains(r['writeKey']));
    expect(seen, contains(null));
    // A call its scopes do not cover never reaches the application.
    expect(
      seen.where((Object? s) => s != null && s != r['writeKey']),
      hasLength(3),
    );
  });

  test('a key reaches no route that declares no policy action', () {
    expect(status('noPolicy'), 403);
    // The route itself is open; it is the key that is refused.
    expect(status('noPolicyAnonymous'), 200);
  });

  test('requests without a platform credential are the application\'s', () {
    expect(status('anonymous'), 200);
    expect(status('appBearer'), 200);
  });

  test('an OAuth token is refused where OAuth is not enabled', () {
    expect(status('oauthDisabled'), 401);
  });

  test('a key over its rate plan is throttled', () {
    final List<Object?> limited = r['limited']! as List<Object?>;
    expect(
      <Object?>[for (final Object? l in limited) (l! as Map)['status']],
      <int>[200, 200, 429],
    );
  });

  test('no secret is printed or answered', () {
    final Map<String, Object?> answers = Map<String, Object?>.of(r)
      ..remove('secrets');
    // Everything the process printed except the probe's own report, which
    // carries the secrets so this test can look for them.
    final String printed = const LineSplitter()
        .convert(output)
        .where((String l) => !l.startsWith('PROBE '))
        .join('\n');
    final List<Object?> secrets = r['secrets']! as List<Object?>;
    expect(secrets, hasLength(4));
    for (final Object? secret in secrets) {
      expect('$secret', startsWith('dvk_'));
      expect(printed, isNot(contains('$secret')));
      expect(jsonEncode(answers), isNot(contains('$secret')));
    }
  });
}
