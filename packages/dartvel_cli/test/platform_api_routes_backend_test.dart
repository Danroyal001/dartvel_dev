// GraphQL, the crash endpoint, OpenAPI and health through the authentication
// stage every other generated route runs.
//
// Each was registered bare: no tenant scope and no authentication stage. So a
// key presented for the wrong tenant was refused with a 401 on a backend
// function's route and not looked at on /graphql, where a mutation ran with
// nothing checked -- the scopes a key carries were enforced on the route of
// the function a mutation resolves through and not on the mutation. This
// generates a real backend with dartvel.platformApi and the crash endpoint
// declared, starts it in a child process, and calls every one of those routes
// over HTTP with real keys.
//
// The silent failures:
//  * a key for another tenant accepted on /graphql, /graphql/stream or the
//    crash endpoint, which reads or writes that tenant's data with a valid
//    credential;
//  * a GraphQL mutation reaching a resolver its key's scopes do not cover;
//  * a GraphQL field declaring no policy answering a key, where no scope can
//    have been checked;
//  * a refusal on these routes that differs from the one every other route
//    gives, which tells a caller which routes check credentials;
//  * a public document (OpenAPI, health) refusing the valid key a partner's
//    tooling sends on every request.
@Timeout(Duration(minutes: 12))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:routes_probe/dartvel_client/platform_api.g.dart' as api;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<Map<String, Object?>> call(
  int port,
  String method,
  String path, {
  String? bearer,
  String tenant = 'acme',
  Object? json,
  List<int>? bytes,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-tenant', tenant);
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (json != null || bytes != null) {
      request.headers.contentType = ContentType.json;
      request.add(bytes ?? utf8.encode(jsonEncode(json)));
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

List<int> report(String id) => utf8.encode(jsonEncode(DVCrashReport(
      id: id,
      kind: DVCrashKind.fatal,
      errorType: 'StateError',
      message: 'boom',
      frames: const <DVCrashFrame>[DVCrashFrame(function: 'main')],
      fingerprint: 'f',
      context: DVCrashContext(release: '1.0.0', installId: 'install-$id'),
      occurredAt: DateTime.utc(2026, 9, 14),
    ).toJson()));

Future<void> main() async {
  final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
  const DVDatabase().configure(db);

  final DVApiKeys keys = DVApiKeys(
    database: db,
    scopes: api.dartvelPlatformApi!.scopes,
  );
  await keys.ensureSchema();
  final DVIssuedApiKey read =
      await keys.issue(tenant: 'acme', scopes: <String>['orders:read']);
  final DVIssuedApiKey write =
      await keys.issue(tenant: 'acme', scopes: <String>['orders:write']);

  final List<String> ran = <String>[];
  DVGraphQL.registerQuery(DVGraphQLField('orders', 'String!',
      policy: 'Order.view', resolve: (Map<String, Object?> a, Object? p) {
    ran.add('orders:${DVApiPrincipal.current?.subject}');
    return const DVTenants().currentTenant;
  }));
  DVGraphQL.registerQuery(DVGraphQLField('open', 'String!',
      resolve: (Map<String, Object?> a, Object? p) {
    ran.add('open:${DVApiPrincipal.current?.subject}');
    return 'open';
  }));
  // Resolves through what the orders.post backend function does, under the
  // same Resource.action that function's route declares.
  DVGraphQL.registerMutation(DVGraphQLField('createOrder', 'String!',
      policy: 'Order.create', resolve: (Map<String, Object?> a, Object? p) {
    ran.add('createOrder:${DVApiPrincipal.current?.subject}');
    return 'created';
  }));
  DVGraphQL.registerSubscription(DVGraphQLField('orderCreated', 'String!',
      policy: 'Order.create', resolve: (Map<String, Object?> a, Object? p) {
    ran.add('orderCreated:${DVApiPrincipal.current?.subject}');
    return Stream<String>.value('o1');
  }));

  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  const String unknown = 'dvk_0123456789abcdef_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  final Map<String, Object?> out = <String, Object?>{};
  Map<String, Object?> gql(String query) => <String, Object?>{'query': query};
  try {
    // The refusal every generated route gives, for comparison.
    out['routeUnknown'] = await call(port, 'GET', '/api/orders', bearer: unknown);
    out['routeOtherTenant'] =
        await call(port, 'GET', '/api/orders', bearer: read.secret, tenant: 'globex');

    out['gqlOtherTenant'] = await call(port, 'POST', '/api/graphql',
        bearer: read.secret, tenant: 'globex', json: gql('{ orders }'));
    out['gqlUnknown'] = await call(port, 'POST', '/api/graphql',
        bearer: unknown, json: gql('{ orders }'));
    out['gqlReadCreate'] = await call(port, 'POST', '/api/graphql',
        bearer: read.secret, json: gql('mutation { createOrder }'));
    out['gqlWriteCreate'] = await call(port, 'POST', '/api/graphql',
        bearer: write.secret, json: gql('mutation { createOrder }'));
    out['gqlReadOrders'] = await call(port, 'POST', '/api/graphql',
        bearer: read.secret, json: gql('{ orders }'));
    out['gqlKeyOpen'] = await call(port, 'POST', '/api/graphql',
        bearer: read.secret, json: gql('{ open }'));
    out['gqlAnonymousOpen'] =
        await call(port, 'POST', '/api/graphql', json: gql('{ open }'));
    out['streamOtherTenant'] = await call(port, 'POST', '/api/graphql/stream',
        bearer: read.secret, tenant: 'globex',
        json: gql('subscription { orderCreated }'));
    out['streamReadCreate'] = await call(port, 'POST', '/api/graphql/stream',
        bearer: read.secret, json: gql('subscription { orderCreated }'));
    out['schemaOtherTenant'] = await call(port, 'GET', '/api/graphql/schema',
        bearer: read.secret, tenant: 'globex');
    out['schemaAnonymous'] = await call(port, 'GET', '/api/graphql/schema');

    out['crashOtherTenant'] = await call(port, 'POST', '/api/_dartvel/crashes',
        bearer: read.secret, tenant: 'globex', bytes: report('a'));
    out['crashKey'] = await call(port, 'POST', '/api/_dartvel/crashes',
        bearer: read.secret, bytes: report('b'));
    out['crashAnonymous'] =
        await call(port, 'POST', '/api/_dartvel/crashes', bytes: report('c'));

    out['openapiOtherTenant'] = await call(port, 'GET', '/api/openapi.json',
        bearer: read.secret, tenant: 'globex');
    out['openapiKey'] =
        await call(port, 'GET', '/api/openapi.json', bearer: read.secret);
    out['openapiAnonymous'] = await call(port, 'GET', '/api/openapi.json');

    out['healthOtherTenant'] = await call(port, 'GET', '/api/health',
        bearer: read.secret, tenant: 'globex');
    out['healthKey'] = await call(port, 'GET', '/api/health', bearer: read.secret);
    out['healthAnonymous'] = await call(port, 'GET', '/api/health');
  } finally {
    await handle.stop();
  }
  out['ran'] = ran;
  out['read'] = read.key.id;
  out['write'] = write.key.id;
  out['stored'] =
      (await const DVDatabase().query('SELECT * FROM dv_crash_reports')).length;
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
  late Map<String, Object?> r;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_platform_routes_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: routes_probe
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
  crashes:
    sink: dartvel
  platformApi:
    scopes:
      orders:read: [Order.view]
      orders:write: [Order.create]
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
  bool view(Object? user, Order? order) => true;
  bool create(Object? user, Order? order) => true;
}
''');
    write('lib/backend/functions/orders.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: 'Order.view')
Future<String> _listOrders() async => 'orders';
''');
    write('lib/backend/functions/orders.post.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: 'Order.create')
Future<String> _createOrder() async => 'created';
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

    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 4));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    r = jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
  int status(String key) => at(key)['status']! as int;
  List<String> ran() =>
      (r['ran']! as List<Object?>).map((Object? e) => '$e').toList();

  void refusedLikeEveryRoute(String key) {
    expect(status(key), 401, reason: '$key: ${at(key)}');
    expect(at(key)['body'], at('routeUnknown')['body'], reason: key);
    expect(at(key)['www'], at('routeUnknown')['www'], reason: key);
  }

  test('the comparison route refuses a bad credential', () {
    expect(status('routeUnknown'), 401);
    expect(status('routeOtherTenant'), 401);
  });

  test('GraphQL refuses a key for another tenant, as every route does', () {
    refusedLikeEveryRoute('gqlOtherTenant');
    refusedLikeEveryRoute('gqlUnknown');
    refusedLikeEveryRoute('streamOtherTenant');
    refusedLikeEveryRoute('schemaOtherTenant');
    // Only the read key on its own tenant ran the orders resolver: neither the
    // other tenant's request nor the unknown key reached it.
    expect(ran().where((String e) => e.startsWith('orders:')),
        <String>['orders:${r['read']}'],
        reason: 'no resolver runs for a refused credential');
  });

  test('a mutation its key\'s scopes do not cover never runs', () {
    expect(status('gqlReadCreate'), 200);
    expect(at('gqlReadCreate')['body'], contains('Order.create'));
    expect(ran(), isNot(contains('createOrder:${r['read']}')));
    expect(status('streamReadCreate'), 200);
    expect(at('streamReadCreate')['body'], contains('Order.create'));
    expect(ran(), isNot(contains('orderCreated:${r['read']}')));
  });

  test('a mutation its key\'s scopes cover runs as that key', () {
    expect(jsonDecode(at('gqlWriteCreate')['body']! as String),
        <String, Object?>{
          'data': <String, Object?>{'createOrder': 'created'},
        });
    expect(ran(), contains('createOrder:${r['write']}'));
    // And on the request's tenant.
    expect(jsonDecode(at('gqlReadOrders')['body']! as String),
        <String, Object?>{
          'data': <String, Object?>{'orders': 'acme'},
        });
  });

  test('a field that declares no policy answers no key', () {
    expect(at('gqlKeyOpen')['body'], contains('errors'));
    expect(ran(), isNot(contains('open:${r['read']}')));
    expect(jsonDecode(at('gqlAnonymousOpen')['body']! as String),
        <String, Object?>{
          'data': <String, Object?>{'open': 'open'},
        });
  });

  test('the crash endpoint refuses a key for another tenant, and takes none',
      () {
    refusedLikeEveryRoute('crashOtherTenant');
    // A key is not how an install reports a crash, and the endpoint declares
    // no action a scope could cover.
    expect(status('crashKey'), 403);
    expect(status('crashAnonymous'), inInclusiveRange(200, 202),
        reason: '${at('crashAnonymous')}');
    expect(r['stored'], 1);
  });

  test('OpenAPI and health judge a credential and stay public', () {
    refusedLikeEveryRoute('openapiOtherTenant');
    refusedLikeEveryRoute('healthOtherTenant');
    for (final String key in <String>[
      'openapiKey',
      'openapiAnonymous',
      'healthKey',
      'healthAnonymous',
      'schemaAnonymous',
    ]) {
      expect(status(key), 200, reason: '$key: ${at(key)}');
    }
  });
}
