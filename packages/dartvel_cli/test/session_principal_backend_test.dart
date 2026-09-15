// The application's own session through the generated backend's lifecycle.
//
// Only an API key or an OAuth token became a principal on a generated route,
// so a person signed in with the application's own session reached the route
// policy with no caller and every session-authenticated route that wanted a
// real decision needed DVBackendPolicy.decide. This generates a real backend
// with an account store, a sign-in and policies that check the account,
// starts it in a child process, and calls it over HTTP -- asserting on what it
// answered, never on the generated text.
//
// The silent failures:
//  * a revoked, rotated-away or unknown session still reaching the function,
//    as an anonymous request or as its old user;
//  * a session issued on one tenant authorizing on another;
//  * a caller whose role was read at sign-in, so a demotion mid-session does
//    nothing until the session ends;
//  * CSRF skipped because the request now has a principal, which is exactly
//    the exemption an API key gets and a browser session must not;
//  * the API key path regressing, or the application's own bearer tokens
//    swallowed and refused as sessions.
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
import 'package:session_probe/auth/accounts.dart';
import 'package:session_probe/dartvel_client/platform_api.g.dart' as api;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

const String csrfToken = 'probe0csrf0token0that0is0long0enough';

Future<Map<String, Object?>> call(
  int port,
  String method,
  String path, {
  String? bearer,
  String? cookie,
  String tenant = 'acme',
  bool csrf = true,
  Object? body,
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-tenant', tenant);
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    if (cookie != null) request.headers.set('cookie', cookie);
    if (method != 'GET') {
      if (csrf) request.headers.set('x-dartvel-csrf-token', csrfToken);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body ?? <String, Object?>{}));
    }
    final HttpClientResponse response = await request.close();
    return <String, Object?>{
      'status': response.statusCode,
      'body': await response.transform(utf8.decoder).join(),
      'www': response.headers.value('www-authenticate'),
      'cacheControl': response.headers.value('cache-control'),
      'setCookie': response.headers[HttpHeaders.setCookieHeader]?.join('\n'),
    };
  } finally {
    client.close(force: true);
  }
}

Future<String> signIn(int port, String email, {String tenant = 'acme'}) async {
  final Map<String, Object?> answer = await call(port, 'POST', '/api/sign_in',
      tenant: tenant,
      body: <String, Object?>{'email': email, 'password': probePassword});
  if (answer['status'] != 200) throw StateError('sign-in failed: $answer');
  // A String result is sent as text; tolerate a JSON string as well.
  final String text = (answer['body']! as String).trim();
  return text.startsWith('"') ? jsonDecode(text) as String : text;
}

Future<void> main() async {
  final String mode = Platform.environment['PROBE_MODE'] ?? 'installed';
  final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
  const DVDatabase().configure(db);
  DVGraphQL.limits =
      const DVGraphQLLimits(introspection: DVGraphQLIntrospection.authenticated);

  final AuthUser admin = (await provider.signUp('admin@acme.test', probePassword))!;
  final AuthUser viewer = (await provider.signUp('viewer@acme.test', probePassword))!;
  roles[admin.id] = 'admin';
  roles[viewer.id] = 'viewer';
  final Map<String, Object?> out = <String, Object?>{
    'adminId': admin.id,
    'viewerId': viewer.id,
  };

  if (mode == 'default') {
    // Nothing installed by the application: the generated server installs a
    // session stage over the application's database, with no user resolver.
    final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
    final int port = handle.port as int;
    try {
      final String token = await signIn(port, 'admin@acme.test');
      out['token'] = token;
      out['whoami'] = await call(port, 'GET', '/api/whoami', bearer: token);
      out['storedSessions'] =
          (await db.query('SELECT id, tenant FROM dv_sessions')).length;
    } finally {
      await handle.stop();
    }
    stdout.writeln('PROBE ${jsonEncode(out)}');
    exit(0);
  }

  // The application's own stage, installed before the server starts, which
  // reads the account again on every request.
  DVSessionAuthentication.install(resolveUser: accountFor);

  final DVOrganizations orgs = DVOrganizations(database: db);
  await orgs.ensureSchema();
  final DVOrganization acme =
      await orgs.create(name: 'Acme', tenant: 'acme', ownerId: admin.id);
  final DVApiKeys keys = DVApiKeys(
    database: db,
    scopes: api.dartvelPlatformApi!.scopes,
    organizations: orgs,
  );
  await keys.ensureSchema();
  final DVIssuedApiKey read =
      await keys.issue(organization: acme, scopes: <String>['orders:read']);
  final DVIssuedApiKey write =
      await keys.issue(organization: acme, scopes: <String>['orders:write']);

  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final DVSessions sessions = DVSessionAuthentication.sessions;
  try {
    final String adminToken = await signIn(port, 'admin@acme.test');
    final String viewerToken = await signIn(port, 'viewer@acme.test');
    out['tokens'] = <String>[adminToken, viewerToken];
    out['signInWithoutCsrf'] = await call(port, 'POST', '/api/sign_in',
        csrf: false,
        body: <String, Object?>{
          'email': 'admin@acme.test',
          'password': probePassword,
        });

    // --- the session stage ---------------------------------------------
    out['whoamiAnonymous'] = await call(port, 'GET', '/api/whoami');
    out['whoamiSession'] =
        await call(port, 'GET', '/api/whoami', bearer: adminToken);
    out['whoamiCookie'] = await call(port, 'GET', '/api/whoami',
        cookie: 'theme=dark; __Host-dv_session=$adminToken');
    out['whoamiAppBearer'] =
        await call(port, 'GET', '/api/whoami', bearer: 'app-session-token');
    out['whoamiKey'] =
        await call(port, 'GET', '/api/whoami', bearer: read.secret);
    out['whoamiUnknown'] =
        await call(port, 'GET', '/api/whoami', bearer: 'dvs_${'C' * 43}');
    out['whoamiOtherTenant'] = await call(port, 'GET', '/api/whoami',
        bearer: adminToken, tenant: 'globex');

    roles[admin.id] = 'viewer';
    out['whoamiDemoted'] =
        await call(port, 'GET', '/api/whoami', bearer: adminToken);
    roles[admin.id] = 'admin';

    final DVIssuedSession rotated = await sessions.rotate(adminToken);
    out['whoamiRotatedAway'] =
        await call(port, 'GET', '/api/whoami', bearer: adminToken);
    out['whoamiRotated'] =
        await call(port, 'GET', '/api/whoami', bearer: rotated.token);

    await sessions.revoke(rotated.session.id);
    out['whoamiRevoked'] =
        await call(port, 'GET', '/api/whoami', bearer: rotated.token);
    out['whoamiRevokedCookie'] = await call(port, 'GET', '/api/whoami',
        cookie: '__Host-dv_session=${rotated.token}');
    out['healthRevoked'] =
        await call(port, 'GET', '/api/health', bearer: rotated.token);

    const String introspection = '{"query": "{ __schema { queryType { name } } }"}';
    out['graphqlAnonymous'] = await call(port, 'POST', '/api/graphql',
        body: jsonDecode(introspection));
    out['graphqlSession'] = await call(port, 'POST', '/api/graphql',
        bearer: viewerToken, body: jsonDecode(introspection));

    // --- route policies asked about the signed-in account -----------------
    final String secondAdmin = await signIn(port, 'admin@acme.test');
    (out['tokens']! as List<String>).add(secondAdmin);
    out['viewViewer'] =
        await call(port, 'GET', '/api/orders', bearer: viewerToken);
    out['removeViewer'] =
        await call(port, 'GET', '/api/remove', bearer: viewerToken);
    out['removeAdmin'] =
        await call(port, 'GET', '/api/remove', bearer: secondAdmin);
    roles[admin.id] = 'viewer';
    out['removeDemoted'] =
        await call(port, 'GET', '/api/remove', bearer: secondAdmin);
    roles[admin.id] = 'admin';
    out['createViewer'] =
        await call(port, 'POST', '/api/orders', bearer: viewerToken);
    out['createAdmin'] =
        await call(port, 'POST', '/api/orders', bearer: secondAdmin);
    out['createWriteKey'] =
        await call(port, 'POST', '/api/orders', bearer: write.secret);
    out['createReadKey'] =
        await call(port, 'POST', '/api/orders', bearer: read.secret);

    // --- refusals: nobody signed in, or somebody who may not -------------
    out['viewAnonymous'] = await call(port, 'GET', '/api/orders');
    out['removeAnonymous'] = await call(port, 'GET', '/api/remove');
    out['viewReadKey'] =
        await call(port, 'GET', '/api/orders', bearer: read.secret);
    out['createAnonymous'] = await call(port, 'POST', '/api/orders');
    out['createAdminWithoutCsrf'] = await call(port, 'POST', '/api/orders',
        bearer: secondAdmin, csrf: false);
    out['createAdminCookieWithoutCsrf'] = await call(port, 'POST', '/api/orders',
        cookie: '__Host-dv_session=$secondAdmin', csrf: false);
    out['createWriteKeyWithoutCsrf'] = await call(port, 'POST', '/api/orders',
        bearer: write.secret, csrf: false);
  } finally {
    await handle.stop();
  }
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

String _function(String policy, String name, String answer) => '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: '$policy')
Future<String> _$name() async => '$answer';
''';

void main() {
  late Directory project;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_session_principal_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: session_probe
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
      orders:read: [Order.view, Order.viewAny]
      orders:write: [Order.create]
''');
    write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
    // The application's user, as the server holds it: a plain class over
    // dartvel_core. A generated model reaches Flutter, which a server cannot
    // load, so this is the representation a server-side policy is written
    // against.
    write('lib/auth/accounts.dart', '''
import 'package:dartvel_core/dartvel.dart';

const String probePassword = 'correct horse battery staple';

final LocalAuthProvider provider = LocalAuthProvider();

/// Each account's role, by user id. Changed while sessions are live.
final Map<String, String> roles = <String, String>{};

class Account {
  const Account(this.id, this.role);

  final String id;
  final String role;
}

/// The account a session belongs to, as it is now.
Account? accountFor(DVSession session) {
  final String? role = roles[session.userId];
  return role == null ? null : Account(session.userId, role);
}
''');
    write('lib/policies/order_policy.dart', '''
import 'package:dartvel_core/dartvel.dart';
import 'package:session_probe/auth/accounts.dart';

class Order {
  const Order();
}

@DVPolicy(Order)
class OrderPolicy {
  /// Anybody, signed in or not.
  bool viewAny(Object? user, Order? order) => true;

  /// A signed-in account.
  bool view(Account user, Order? order) => true;

  /// A key with the scope, or a signed-in account that is not a viewer.
  bool create(Object? user, Order? order) =>
      user is DVApiPrincipal || (user is Account && user.role != 'viewer');

  /// An admin account.
  bool delete(Account user, Order? order) => user.role == 'admin';
}
''');
    write('lib/backend/functions/sign_in.post.dart', '''
import 'package:dartvel_core/dartvel.dart';
import 'package:session_probe/auth/accounts.dart';

/// Checks the password and starts a session on the request's tenant.
Future<String> startSession(String email, String password) async {
  final AuthUser? user = await provider.signIn(email, password);
  return (await DVSessionAuthentication.sessions.create(user!.id)).token;
}

@DVBackendFunction()
Future<String> _signIn(String email, String password) async =>
    startSession(email, password);
''');
    write('lib/backend/functions/whoami.get.dart', '''
import 'package:dartvel_core/dartvel.dart';
import 'package:session_probe/auth/accounts.dart';

/// Who the injected context says is calling.
String describeCaller(DVContext context) {
  final DVSessionPrincipal? session = context.session;
  if (session == null) return context.apiPrincipal == null ? 'anonymous' : 'key';
  final Object? user = context.user;
  return '\${session.userId}@\${session.tenant}:\${user is Account ? user.role : '-'}';
}

@DVBackendFunction(policy: 'Order.viewAny')
Future<String> _whoami(DVContext context) async => describeCaller(context);
''');
    write('lib/backend/functions/orders.get.dart',
        _function('Order.view', 'listOrders', 'orders'));
    write('lib/backend/functions/orders.post.dart',
        _function('Order.create', 'createOrder', 'created'));
    write('lib/backend/functions/remove.get.dart',
        _function('Order.delete', 'remove', 'deleted'));
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

  Future<Map<String, Object?>> probe(
      [Map<String, String> environment = const <String, String>{}]) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
      environment: environment,
    ).timeout(const Duration(minutes: 4));
    final String output = '${result.stdout}\n${result.stderr}';
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n$output');
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  group('a served backend with the application\'s own sessions', () {
    late Map<String, Object?> r;

    setUpAll(() async {
      r = await probe();
    });

    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
    int status(String key) => at(key)['status']! as int;
    String body(String key) => at(key)['body']! as String;
    String adminId() => r['adminId']! as String;

    void expectUnauthorized(String key) {
      expect(status(key), 401, reason: '$key: ${at(key)}');
      expect(at(key)['www'], 'Bearer error="invalid_token"', reason: key);
      expect(at(key)['cacheControl'], 'no-store', reason: key);
      for (final Object? token in r['tokens']! as List<Object?>) {
        expect(body(key), isNot(contains('$token')), reason: key);
      }
    }

    group('the authentication stage', () {
      test('a sign-in issues a session token', () {
        expect(r['tokens'], everyElement(startsWith('dvs_')));
      });

      test('a session reaches the function through the injected DVContext',
          () {
        expect(status('whoamiAnonymous'), 200);
        expect(body('whoamiAnonymous'), contains('anonymous'));
        expect(status('whoamiSession'), 200, reason: '${at('whoamiSession')}');
        expect(body('whoamiSession'), contains('${adminId()}@acme:admin'));
      });

      test('the session cookie is the same session', () {
        expect(status('whoamiCookie'), 200, reason: '${at('whoamiCookie')}');
        expect(body('whoamiCookie'), contains('${adminId()}@acme:admin'));
      });

      test('an API key is still the platform API\'s, and other bearers the '
          'application\'s', () {
        expect(status('whoamiKey'), 200, reason: '${at('whoamiKey')}');
        expect(body('whoamiKey'), contains('key'));
        expect(status('whoamiAppBearer'), 200);
        expect(body('whoamiAppBearer'), contains('anonymous'));
      });

      test('an unknown session is refused rather than read as anonymous', () {
        expectUnauthorized('whoamiUnknown');
      });

      test('a session from another tenant is refused on this one', () {
        expectUnauthorized('whoamiOtherTenant');
      });

      test('the account is read on the request, so a demotion applies at once',
          () {
        expect(body('whoamiDemoted'), contains('${adminId()}@acme:viewer'));
      });

      test('a rotated-away token is refused and its replacement accepted', () {
        expectUnauthorized('whoamiRotatedAway');
        expect(status('whoamiRotated'), 200);
        expect(body('whoamiRotated'), contains('${adminId()}@acme:admin'));
      });

      test('a revoked session fails its next request, on any route', () {
        expectUnauthorized('whoamiRevoked');
        expectUnauthorized('healthRevoked');
      });

      test('a refused cookie is cleared, so the browser can sign in again', () {
        expect(status('whoamiRevokedCookie'), 401);
        expect(at('whoamiRevokedCookie')['setCookie'],
            allOf(contains('__Host-dv_session='), contains('Max-Age=0')));
      });

      test('GraphQL counts a session as authenticated', () {
        expect(status('graphqlSession'), 200);
        expect(body('graphqlSession'), contains('queryType'));
        expect(body('graphqlSession'), isNot(contains('errors')));
        expect(body('graphqlAnonymous'), contains('errors'));
      });

      test('a sign-in is still a state-changing request that needs CSRF', () {
        expect(status('signInWithoutCsrf'), 403);
      });
    });

    group('route policies', () {
      test('a policy written against the account is handed the account', () {
        expect(status('viewViewer'), 200, reason: '${at('viewViewer')}');
        expect(body('viewViewer'), 'orders');
      });

      test('the policy decides by the account\'s role', () {
        expect(status('removeViewer'), 403, reason: '${at('removeViewer')}');
        expect(status('removeAdmin'), 200, reason: '${at('removeAdmin')}');
        expect(body('removeAdmin'), 'deleted');
      });

      test('a role changed mid-session is the role the next request is asked '
          'with', () {
        expect(status('removeDemoted'), 403, reason: '${at('removeDemoted')}');
      });

      test('a policy taking Object? tells an account from a key', () {
        expect(status('createViewer'), 403, reason: '${at('createViewer')}');
        expect(status('createAdmin'), 200, reason: '${at('createAdmin')}');
        expect(body('createAdmin'), 'created');
        expect(status('createWriteKey'), 200, reason: '${at('createWriteKey')}');
        expect(status('createReadKey'), 403,
            reason: 'outside the key\'s scopes: ${at('createReadKey')}');
      });
    });

    group('refusals', () {
      test('no session on a route whose policy needs a signed-in user is 401',
          () {
        for (final String key in <String>['viewAnonymous', 'removeAnonymous']) {
          expect(status(key), 401, reason: '$key: ${at(key)}');
          expect(at(key)['www'], 'Bearer', reason: key);
          expect(at(key)['cacheControl'], 'no-store', reason: key);
        }
      });

      test('a caller the policy cannot take is 403, not asked to sign in', () {
        expect(status('viewReadKey'), 403, reason: '${at('viewReadKey')}');
      });

      test('a policy that answers without a caller refuses with 403', () {
        expect(status('createAnonymous'), 403,
            reason: '${at('createAnonymous')}');
      });

      test('a session-authenticated state change still needs a CSRF token', () {
        for (final String key in <String>[
          'createAdminWithoutCsrf',
          'createAdminCookieWithoutCsrf',
        ]) {
          expect(status(key), 403, reason: '$key: ${at(key)}');
          expect(body(key), contains('CSRF'), reason: key);
        }
      });

      test('an API key is still exempt from CSRF', () {
        expect(status('createWriteKeyWithoutCsrf'), 200,
            reason: '${at('createWriteKeyWithoutCsrf')}');
      });
    });
  });

  test('with nothing installed, the server keeps sessions in its database',
      () async {
    final Map<String, Object?> r =
        await probe(const <String, String>{'PROBE_MODE': 'default'});
    final Map<String, Object?> whoami = r['whoami']! as Map<String, Object?>;

    expect(r['token'], startsWith('dvs_'));
    expect(whoami['status'], 200, reason: '$whoami');
    expect(whoami['body'], contains('${r['adminId']}@acme:-'));
    expect(r['storedSessions'], 1);
  });
}
