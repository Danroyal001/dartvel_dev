// The OAuth provider's HTTP endpoints, served by a generated backend.
//
// DVOAuthProvider could validate an authorization, exchange a code, refresh,
// introspect and revoke, and no generated backend served any of it: an
// application that declared itself an OAuth provider had no authorization
// endpoint, no token endpoint and no metadata document. This generates a real
// backend with `dartvel.platformApi.oauth` on, starts it, and drives the whole
// flow over HTTP the way a partner's client would.
//
// The silent failures, each asserted against:
//  * introspection answering a caller that did not authenticate, which turns
//    the endpoint into an oracle for whether a stolen token still works;
//  * a code or refresh exchange accepted as GET or as a JSON body, where the
//    RFCs require a form POST -- and a refused one that still burnt the code;
//  * a token, code or secret echoed in a log line or an error body;
//  * a token response a cache may keep;
//  * a mismatched redirect URI redirected to;
//  * CORS on the authorization endpoint, which is a browser navigation, and
//    none on the token endpoint a browser-based client has to call;
//  * a token accepted for another tenant.
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

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

late int port;
final List<String> secrets = <String>[];
final List<String> errorBodies = <String>[];

String basic(String id, String secret) =>
    'Basic ${base64.encode(utf8.encode('${Uri.encodeQueryComponent(id)}:${Uri.encodeQueryComponent(secret)}'))}';

String form(Map<String, String> fields) => Uri(queryParameters: fields).query;

Future<Map<String, Object?>> send(
  String method,
  String path, {
  Map<String, String> headers = const <String, String>{},
  String? body,
  String contentType = 'application/x-www-form-urlencoded',
  String tenant = 'acme',
}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.followRedirects = false;
    request.headers.set('x-tenant', tenant);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.set('content-type', contentType);
      request.write(body);
    }
    final HttpClientResponse response = await request.close();
    final String text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) errorBodies.add(text);
    return <String, Object?>{
      'status': response.statusCode,
      'body': text,
      for (final String h in <String>[
        'location',
        'cache-control',
        'pragma',
        'content-type',
        'www-authenticate',
        'access-control-allow-origin',
        'allow',
      ])
        h: response.headers.value(h),
    };
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> json(Map<String, Object?> response) =>
    jsonDecode(response['body']! as String) as Map<String, Object?>;

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  DVBackendPolicy.decide = (String policy, String path) async => true;
  // Who is signed in is the application's auth: here, a header.
  DVOAuthEndpoints.resolveUser =
      (Request request) async => request.headers.get('x-probe-user');
  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{'port': port};
  try {
    final DVPlatformApi platform = DVPlatformApi.installed!;
    final DVOAuthProvider oauth = (await platform.oauthProvider())!;
    final DVOrganizations orgs = await platform.organizations();
    final DVApiKeys keys = await platform.keys();
    final DVOrganization acme =
        await orgs.create(name: 'Acme', tenant: 'acme', ownerId: 'ada');
    final DVRegisteredOAuthClient web = await oauth.registerClient(
      name: 'Partner Web',
      redirectUris: <String>['https://partner.example/cb'],
      scopes: <String>['orders:read'],
      organization: acme,
    );
    final DVRegisteredOAuthClient spa = await oauth.registerClient(
      name: 'Partner SPA',
      redirectUris: <String>['https://partner.example/spa'],
      scopes: <String>['orders:read'],
      public: true,
    );
    final DVIssuedApiKey plainKey =
        await keys.issue(organization: acme, scopes: <String>['orders:read']);
    final DVIssuedApiKey introspector = await keys
        .issue(organization: acme, scopes: <String>['tokens:introspect']);
    secrets.addAll(<String>[web.secret!, plainKey.secret, introspector.secret]);

    const String verifier =
        'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk0123456789abcdefgh';
    final String challenge = base64Url
        .encode(crypto.sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final Map<String, String> query = <String, String>{
      'response_type': 'code',
      'client_id': web.client.id,
      'redirect_uri': 'https://partner.example/cb',
      'scope': 'orders:read',
      'state': 'xyz',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    };
    String q(Map<String, String> fields) => Uri(queryParameters: fields).query;
    final String csrf = 'c' * 40;
    final String webAuth = basic(web.client.id, web.secret!);

    out['authorize'] = await send('GET', '/api/oauth/authorize?${q(query)}');
    out['authorizeBadRedirect'] = await send('GET',
        '/api/oauth/authorize?${q(<String, String>{...query, 'redirect_uri': 'https://evil.example/cb'})}');
    out['authorizeNoPkce'] = await send('GET',
        '/api/oauth/authorize?${q(<String, String>{...query}..remove('code_challenge'))}');
    out['authorizePreflight'] = await send('OPTIONS', '/api/oauth/authorize',
        headers: <String, String>{'origin': 'https://partner.example'});
    out['describe'] =
        await send('GET', '/api/oauth/authorize/request?${q(query)}');

    final String approval = form(<String, String>{...query, 'decision': 'approve'});
    out['approveAnonymous'] = await send('POST', '/api/oauth/authorize',
        body: approval,
        headers: <String, String>{DVCSRF.headerName: csrf});
    out['approveNoCsrf'] = await send('POST', '/api/oauth/authorize',
        body: approval, headers: <String, String>{'x-probe-user': 'ada'});
    final Map<String, Object?> approved = await send(
        'POST', '/api/oauth/authorize',
        body: approval,
        headers: <String, String>{'x-probe-user': 'ada', DVCSRF.headerName: csrf});
    out['approve'] = approved;
    final String? redirect = approved['status'] == 200
        ? json(approved)['redirect_to'] as String?
        : null;
    final String code = redirect == null
        ? 'no-code'
        : Uri.parse(redirect).queryParameters['code'] ?? 'no-code';
    secrets.add(code);

    final Map<String, String> exchange = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': 'https://partner.example/cb',
      'code_verifier': verifier,
    };
    out['exchangeGet'] = await send('GET', '/api/oauth/token?${q(exchange)}',
        headers: <String, String>{'authorization': webAuth});
    out['exchangeJson'] = await send('POST', '/api/oauth/token',
        body: jsonEncode(exchange),
        contentType: 'application/json',
        headers: <String, String>{'authorization': webAuth});
    final Map<String, Object?> exchanged = await send('POST', '/api/oauth/token',
        body: form(exchange),
        headers: <String, String>{'authorization': webAuth, 'origin': 'https://partner.example'});
    out['exchange'] = exchanged;
    final Map<String, Object?> tokens =
        exchanged['status'] == 200 ? json(exchanged) : <String, Object?>{};
    final String access = '${tokens['access_token'] ?? 'no-access'}';
    final String refresh = '${tokens['refresh_token'] ?? 'no-refresh'}';
    secrets.addAll(<String>[access, refresh]);

    out['useToken'] = await send('GET', '/api/orders',
        headers: <String, String>{'authorization': 'Bearer $access'});
    out['useTokenOtherTenant'] = await send('GET', '/api/orders',
        headers: <String, String>{'authorization': 'Bearer $access'},
        tenant: 'globex');

    final Map<String, String> refreshing = <String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    };
    out['refreshGet'] = await send('GET', '/api/oauth/token?${q(refreshing)}',
        headers: <String, String>{'authorization': webAuth});
    out['refreshJson'] = await send('POST', '/api/oauth/token',
        body: jsonEncode(refreshing),
        contentType: 'application/json',
        headers: <String, String>{'authorization': webAuth});
    final Map<String, Object?> refreshed = await send('POST', '/api/oauth/token',
        body: form(refreshing),
        headers: <String, String>{'authorization': webAuth});
    out['refresh'] = refreshed;
    final String access2 = refreshed['status'] == 200
        ? '${json(refreshed)['access_token']}'
        : 'no-access-2';
    secrets.add(access2);

    out['duplicate'] = await send('POST', '/api/oauth/token',
        body: 'grant_type=refresh_token&grant_type=client_credentials',
        headers: <String, String>{'authorization': webAuth});
    out['twoAuth'] = await send('POST', '/api/oauth/token',
        body: form(<String, String>{
          'grant_type': 'client_credentials',
          'client_id': web.client.id,
          'client_secret': web.secret!,
        }),
        headers: <String, String>{'authorization': webAuth});
    out['badSecret'] = await send('POST', '/api/oauth/token',
        body: form(<String, String>{'grant_type': 'refresh_token', 'refresh_token': refresh}),
        headers: <String, String>{'authorization': basic(web.client.id, 'dvcs_wrong')});
    out['clientCredentials'] = await send('POST', '/api/oauth/token',
        body: form(<String, String>{'grant_type': 'client_credentials'}),
        headers: <String, String>{
          'authorization': basic(plainKey.key.prefix, plainKey.secret),
        });
    out['tokenPreflight'] = await send('OPTIONS', '/api/oauth/token',
        headers: <String, String>{
          'origin': 'https://partner.example',
          'access-control-request-method': 'POST',
        });

    final String introspection = form(<String, String>{'token': access2});
    out['introspectAnonymous'] =
        await send('POST', '/api/oauth/introspect', body: introspection);
    out['introspectPublic'] = await send('POST', '/api/oauth/introspect',
        body: form(<String, String>{'token': access2, 'client_id': spa.client.id}));
    out['introspectKeyNoScope'] = await send('POST', '/api/oauth/introspect',
        body: introspection,
        headers: <String, String>{'authorization': 'Bearer ${plainKey.secret}'});
    out['introspectKey'] = await send('POST', '/api/oauth/introspect',
        body: introspection,
        headers: <String, String>{
          'authorization': 'Bearer ${introspector.secret}',
        });
    out['introspectClient'] = await send('POST', '/api/oauth/introspect',
        body: introspection, headers: <String, String>{'authorization': webAuth});
    out['introspectOtherTenant'] = await send('POST', '/api/oauth/introspect',
        body: introspection,
        headers: <String, String>{'authorization': webAuth},
        tenant: 'globex');
    out['introspectGet'] = await send(
        'GET', '/api/oauth/introspect?$introspection',
        headers: <String, String>{'authorization': webAuth});

    out['revokeGet'] = await send('GET', '/api/oauth/revoke?$introspection',
        headers: <String, String>{'authorization': webAuth});
    out['revokeAnonymous'] =
        await send('POST', '/api/oauth/revoke', body: introspection);
    out['revoke'] = await send('POST', '/api/oauth/revoke',
        body: introspection, headers: <String, String>{'authorization': webAuth});
    out['afterRevoke'] = await send('GET', '/api/orders',
        headers: <String, String>{'authorization': 'Bearer $access2'});
    out['introspectRevoked'] = await send('POST', '/api/oauth/introspect',
        body: introspection, headers: <String, String>{'authorization': webAuth});

    out['metadata'] =
        await send('GET', '/.well-known/oauth-authorization-server');
  } finally {
    await handle.stop();
  }
  out['secrets'] = secrets;
  out['errorBodies'] = errorBodies;
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
  late String printed;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    project = Directory.systemTemp.createTempSync('dv_platform_oauth_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: oauth_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  crypto: any
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
      orders:read:
        actions: [Order.view]
        description: See your orders
      tokens:introspect: [DVOAuthToken.introspect]
    oauth: true
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
}
''');
    write('lib/backend/functions/orders.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: 'Order.view')
Future<String> _listOrders() async => 'orders';
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
    printed = const LineSplitter()
        .convert(output)
        .where((String l) => !l.startsWith('PROBE '))
        .join('\n');
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
  int status(String key) => at(key)['status']! as int;
  Map<String, Object?> body(String key) =>
      jsonDecode(at(key)['body']! as String) as Map<String, Object?>;

  group('authorization endpoint', () {
    test('a valid request goes to the consent screen with its parameters', () {
      expect(status('authorize'), 302);
      final Uri location = Uri.parse(at('authorize')['location']! as String);
      expect(location.path, '/oauth/consent');
      expect(location.queryParameters['client_id'], isNotEmpty);
      expect(location.queryParameters['state'], 'xyz');
      expect(location.queryParameters['code_challenge_method'], 'S256');
      expect(at('authorize')['cache-control'], contains('no-store'));
    });

    test('a redirect URI the client did not register is never redirected to',
        () {
      expect(status('authorizeBadRedirect'), 400);
      expect(at('authorizeBadRedirect')['location'], isNull);
      expect(at('authorizeBadRedirect')['body'], isNot(contains('evil')));
    });

    test('any other error goes back to the client with its state', () {
      expect(status('authorizeNoPkce'), 302);
      final Uri location =
          Uri.parse(at('authorizeNoPkce')['location']! as String);
      expect(location.host, 'partner.example');
      expect(location.queryParameters['error'], 'invalid_request');
      expect(location.queryParameters['state'], 'xyz');
      expect(location.queryParameters, isNot(contains('code')));
    });

    test('is a navigation, not a cross-origin endpoint', () {
      for (final String key in <String>['authorize', 'authorizePreflight']) {
        expect(at(key)['access-control-allow-origin'], isNull, reason: key);
      }
    });

    test('the consent screen is told the client and the scope wording', () {
      expect(status('describe'), 200);
      expect(body('describe')['client'], containsPair('name', 'Partner Web'));
      expect(body('describe')['scopes'], <Object?>[
        <String, Object?>{'scope': 'orders:read', 'description': 'See your orders'},
      ]);
    });

    test('approval needs a signed-in person and a CSRF token', () {
      expect(status('approveAnonymous'), 401);
      expect(status('approveNoCsrf'), 403);
      expect(status('approve'), 200);
      final Uri redirect =
          Uri.parse(body('approve')['redirect_to']! as String);
      expect(redirect.host, 'partner.example');
      expect(redirect.queryParameters['state'], 'xyz');
      expect(redirect.queryParameters['code'], isNotEmpty);
      expect(at('approve')['cache-control'], contains('no-store'));
    });
  });

  group('token endpoint', () {
    test('a code exchange is a form POST, and a refused one spends nothing',
        () {
      expect(status('exchangeGet'), 405);
      expect(at('exchangeGet')['allow'], 'POST');
      expect(status('exchangeJson'), 400);
      expect(body('exchangeJson')['error'], 'invalid_request');
      // The same code, after both refusals.
      expect(status('exchange'), 200);
      final Map<String, Object?> tokens = body('exchange');
      expect('${tokens['access_token']}', startsWith('dvat_'));
      expect('${tokens['refresh_token']}', startsWith('dvrt_'));
      expect(tokens['token_type'], 'Bearer');
      expect(tokens['scope'], 'orders:read');
    });

    test('a token response is JSON nobody may cache', () {
      for (final String key in <String>['exchange', 'refresh', 'clientCredentials', 'badSecret']) {
        expect(at(key)['content-type'], startsWith('application/json'),
            reason: key);
        expect(at(key)['cache-control'], 'no-store', reason: key);
        expect(at(key)['pragma'], 'no-cache', reason: key);
      }
    });

    test('a browser-based client may call it cross-origin', () {
      expect(at('exchange')['access-control-allow-origin'], '*');
      expect(status('tokenPreflight'), 204);
      expect(at('tokenPreflight')['access-control-allow-origin'], '*');
    });

    test('the access token authenticates on its own tenant only', () {
      expect(status('useToken'), 200);
      expect(status('useTokenOtherTenant'), 401);
    });

    test('a refresh is a form POST too', () {
      expect(status('refreshGet'), 405);
      expect(status('refreshJson'), 400);
      expect(status('refresh'), 200);
      expect('${body('refresh')['access_token']}', startsWith('dvat_'));
    });

    test('a repeated parameter, or two ways of authenticating, is refused', () {
      expect(status('duplicate'), 400);
      expect(body('duplicate')['error'], 'invalid_request');
      expect(status('twoAuth'), 400);
      expect(body('twoAuth')['error'], 'invalid_request');
    });

    test('a client that fails to authenticate is told so by 401', () {
      expect(status('badSecret'), 401);
      expect(body('badSecret')['error'], 'invalid_client');
      expect('${at('badSecret')['www-authenticate']}', startsWith('Basic'));
    });

    test('client credentials is an API key with a grant', () {
      expect(status('clientCredentials'), 200);
      expect(body('clientCredentials'), isNot(contains('refresh_token')));
    });
  });

  group('introspection', () {
    test('answers nobody who has not authenticated', () {
      for (final String key in <String>[
        'introspectAnonymous',
        'introspectPublic',
      ]) {
        expect(status(key), 401, reason: key);
        expect(at(key)['body'], isNot(contains('active')), reason: key);
      }
      expect(status('introspectKeyNoScope'), 403);
      expect(at('introspectKeyNoScope')['body'], isNot(contains('active')));
    });

    test('answers a key whose scopes cover introspection', () {
      expect(status('introspectKey'), 200);
      expect(body('introspectKey')['active'], isTrue);
    });

    test('answers a confidential client, on the request\'s tenant', () {
      expect(status('introspectClient'), 200);
      expect(body('introspectClient')['active'], isTrue);
      expect(body('introspectClient')['scope'], 'orders:read');
      expect(at('introspectClient')['cache-control'], 'no-store');
      expect(body('introspectOtherTenant'), <String, Object?>{'active': false});
    });

    test('is a form POST', () {
      expect(status('introspectGet'), 405);
    });
  });

  group('revocation', () {
    test('a client revokes its token, which then stops working', () {
      expect(status('revokeGet'), 405);
      expect(status('revokeAnonymous'), 401);
      expect(status('revoke'), 200);
      expect(status('afterRevoke'), 401);
      expect(body('introspectRevoked'), <String, Object?>{'active': false});
    });
  });

  test('the RFC 8414 metadata document describes the endpoints', () {
    expect(status('metadata'), 200);
    expect(at('metadata')['content-type'], startsWith('application/json'));
    expect(at('metadata')['access-control-allow-origin'], '*');
    final Map<String, Object?> m = body('metadata');
    final String issuer = 'http://127.0.0.1:${r['port']}';
    expect(m['issuer'], issuer);
    expect(m['authorization_endpoint'], '$issuer/api/oauth/authorize');
    expect(m['token_endpoint'], '$issuer/api/oauth/token');
    expect(m['introspection_endpoint'], '$issuer/api/oauth/introspect');
    expect(m['revocation_endpoint'], '$issuer/api/oauth/revoke');
    expect(m['code_challenge_methods_supported'], <String>['S256']);
    expect(m['response_types_supported'], <String>['code']);
    expect(m['grant_types_supported'],
        containsAll(<String>['authorization_code', 'refresh_token', 'client_credentials']));
    expect(m['scopes_supported'], contains('orders:read'));
  });

  test('no token, code or secret is printed or put in an error', () {
    final List<Object?> secrets = r['secrets']! as List<Object?>;
    expect(secrets, hasLength(greaterThanOrEqualTo(6)));
    final String errors = jsonEncode(r['errorBodies']);
    for (final Object? secret in secrets) {
      expect('$secret', isNot(startsWith('no-')), reason: 'a step failed');
      expect(printed, isNot(contains('$secret')));
      expect(errors, isNot(contains('$secret')));
    }
  });
}
