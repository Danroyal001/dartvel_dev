// @DVPolicy classes, registered by the generated server before it answers.
//
// The client registered them and the server did not, so a route declaring
// @DVBackendFunction(policy: 'Order.view') was answered by
// DVBackendPolicy.decide alone: with no decide it refused a route whose policy
// allowed it, and with a decide that said yes it opened a route whose policy
// nobody had written. This generates a real backend with policy classes in the
// application and in an embedded module, starts it in a child process, and
// calls it over HTTP -- asserting on what it answered, never on the generated
// text.
//
// The silent failures:
//  * a policy class in a merged module the server never registers, so every
//    one of the module's guarded routes refuses (or, with a permissive decide,
//    opens) no matter what its policy says;
//  * a registration that happens after the server is listening, so the first
//    requests are answered by an empty registry;
//  * a generated registration replacing the application's own for the same
//    action and resource;
//  * a policy that needs a resource asked without one and throwing, or worse,
//    allowing;
//  * a route naming a framework action nothing registered, answered anyway.
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
import 'package:policy_probe/dartvel_client/platform_api.g.dart' as api;
import 'package:policy_probe/policies/order_policy.dart';

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

Future<Map<String, Object?>> call(int port, String path, {String? bearer}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.set('x-tenant', 'acme');
    if (bearer != null) request.headers.set('authorization', 'Bearer $bearer');
    final HttpClientResponse response = await request.close();
    return <String, Object?>{
      'status': response.statusCode,
      'body': await response.transform(utf8.decoder).join(),
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final String mode = Platform.environment['PROBE_MODE'] ?? 'serve';
  final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
  const DVDatabase().configure(db);
  const DVAuthAuthorization authorization = DVAuthAuthorization();

  if (mode == 'unregistered') {
    // Nothing answers DVApiKeyResource.viewAny, which a route declares.
    try {
      final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
      await handle.stop();
      stdout.writeln('PROBE ${jsonEncode(<String, Object?>{'started': true})}');
    } on StateError catch (error) {
      stdout.writeln('PROBE ${jsonEncode(<String, Object?>{'refused': error.message})}');
    }
    exit(0);
  }

  final DVApiKeys keys = DVApiKeys(
    database: db,
    scopes: api.dartvelPlatformApi!.scopes,
  );
  await keys.ensureSchema();
  final DVIssuedApiKey read =
      await keys.issue(tenant: 'acme', scopes: <String>['orders:read']);
  final DVIssuedApiKey write =
      await keys.issue(tenant: 'acme', scopes: <String>['orders:write']);

  // The application's own answers, made before the server starts: one for an
  // action a policy class also answers, and one for a framework resource no
  // policy class can be written against here.
  authorization.register<Object?, Order?>(
      'delete', (Object? user, Order? order) => false);
  authorization.register<Object?, DVApiKeyResource?>(
      'viewAny', (Object? user, DVApiKeyResource? resource) => true);

  final Map<String, Object?> out = <String, Object?>{
    'before': authorization.registeredPolicies.contains('view:Order'),
  };
  // Not awaited: whatever is registered by the time startBackend returns was
  // registered before the server could bind, let alone answer.
  final Future<dynamic> starting = gen.startBackend(host: '127.0.0.1', port: 0);
  out['atStart'] = <String>[
    for (final String key in <String>['view:Order', 'view:Note'])
      if (authorization.registeredPolicies.contains(key)) key,
  ];
  final dynamic handle = await starting;
  final int port = handle.port as int;
  try {
    out['view'] = await call(port, '/api/orders');
    out['createAnonymous'] = await call(port, '/api/checkout');
    out['createWrite'] = await call(port, '/api/checkout', bearer: write.secret);
    out['createRead'] = await call(port, '/api/checkout', bearer: read.secret);
    out['needsResource'] = await call(port, '/api/edit');
    out['applicationDenies'] = await call(port, '/api/remove');
    out['moduleNote'] = await call(port, '/api/notes');
    out['frameworkKeys'] = await call(port, '/api/keys');
  } finally {
    await handle.stop();
  }
  // What the process logged about each refusal, which is where a refused
  // route has to say why.
  out['logged'] = <String>[
    for (final DVLogRecord record in DV.ObservabilityAndLogging.recentLogs)
      record.message,
  ];
  stdout.writeln('PROBE ${jsonEncode(out)}');
  exit(0);
}
''';

/// The client's side of the same question: the registrations the generated
/// client makes before a page can ask whether to draw an action, after the
/// application registered its own answer -- which is the order the client
/// runtime runs them in.
const String _clientProbe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:policy_probe/dartvel_client/policies.g.dart' as client;
import 'package:policy_probe/policies/order_policy.dart';

Future<void> main() async {
  const DVAuthAuthorization authorization = DVAuthAuthorization();
  authorization.register<Object?, Order?>(
      'delete', (Object? user, Order? order) => false);
  client.dartvelRegisterPolicies();
  stdout.writeln('PROBE ${jsonEncode(<String, Object?>{
    'view': await authorization.canAction(null, 'Order.view'),
    'delete': await authorization.canAction(null, 'Order.delete'),
    'note': await authorization.canAction(null, 'Note.view'),
  })}');
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
    project = Directory.systemTemp.createTempSync('dv_policy_registration_');
    void write(String relative, String content) {
      File(p.join(project.path, relative))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('pubspec.yaml', '''
name: policy_probe
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
  store:
    path: modules/store
dartvel:
  backendHost: 127.0.0.1
  tenancy:
    source: header
  platformApi:
    scopes:
      orders:read: [Order.view]
      orders:write: [Order.create]
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: embedded
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
  /// Anybody, and a route has no order to show it.
  bool view(Object? user, Order? order) => true;

  /// Only a caller the platform API authenticated.
  bool create(Object? user, Order? order) => user is DVApiPrincipal;

  /// Needs the order, which a route does not have.
  bool update(Object? user, Order order) => true;

  /// Allows; the application's own registration says otherwise.
  bool delete(Object? user, Order? order) => true;
}
''');
    write('lib/backend/functions/orders.get.dart',
        _function('Order.view', 'listOrders', 'orders'));
    write('lib/backend/functions/checkout.get.dart',
        _function('Order.create', 'checkout', 'created'));
    write('lib/backend/functions/edit.get.dart',
        _function('Order.update', 'edit', 'updated'));
    write('lib/backend/functions/remove.get.dart',
        _function('Order.delete', 'remove', 'deleted'));
    write('lib/backend/functions/keys.get.dart',
        _function('DVApiKeyResource.viewAny', 'listKeys', 'keys'));

    // The module: its own package, its own policy, its own guarded route.
    write('modules/store/pubspec.yaml', '''
name: store
publish_to: none
environment:
  sdk: ^3.12.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
dartvel:
  module:
    id: store
    version: 1.0.0
''');
    write('modules/store/lib/policies/note_policy.dart', '''
import 'package:dartvel_core/dartvel.dart';

class Note {
  const Note();
}

@DVPolicy(Note)
class NotePolicy {
  bool view(Object? user, Note? note) => true;
}
''');
    write('modules/store/lib/backend/functions/notes.get.dart',
        _function('Note.view', 'notes', 'notes'));
    write('bin/probe.dart', _probe);
    write('bin/client_probe.dart', _clientProbe);

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

  Future<(Map<String, Object?>, String)> probe(
      [Map<String, String> environment = const <String, String>{},
      String script = 'bin/probe.dart']) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', script],
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
    return (
      jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>,
      output,
    );
  }

  group('a served backend', () {
    late Map<String, Object?> r;

    setUpAll(() async {
      (r, _) = await probe();
    });

    Map<String, Object?> at(String key) => r[key]! as Map<String, Object?>;
    int status(String key) => at(key)['status']! as int;

    test('registers every policy before it can answer', () {
      expect(r['before'], isFalse);
      expect(r['atStart'], <String>['view:Order', 'view:Note']);
    });

    test('answers a route from the policy class with no hand registration',
        () {
      expect(status('view'), 200, reason: '${at('view')}');
      expect(at('view')['body'], 'orders');
    });

    test('answers a module\'s route from the module\'s policy class', () {
      expect(status('moduleNote'), 200, reason: '${at('moduleNote')}');
      expect(at('moduleNote')['body'], 'notes');
    });

    test('the policy sees who is calling, inside the caller\'s scopes', () {
      expect(status('createAnonymous'), 403);
      expect(at('createAnonymous')['body'], contains('Order.create'));
      expect(status('createWrite'), 200, reason: '${at('createWrite')}');
      expect(status('createRead'), 403);
    });

    test('a policy that needs a resource refuses a route, and says why', () {
      expect(status('needsResource'), 403);
      expect(
        r['logged'],
        contains(allOf(contains('Order.update'), contains('nullable'))),
      );
    });

    test('the application\'s own registration wins over the policy class', () {
      expect(status('applicationDenies'), 403);
    });

    test('a framework resource is answered by the application\'s registration',
        () {
      expect(status('frameworkKeys'), 200, reason: '${at('frameworkKeys')}');
    });
  });

  test('the client does not present as allowed what the server refuses',
      () async {
    // The server answered Order.view 200 and Order.delete 403, the second
    // because the application registered its own answer. A client whose
    // generated registration replaced that answer would draw Delete for
    // somebody the server then refuses -- the inconsistency a generated
    // table or form shows as a button that fails.
    final (Map<String, Object?> client, _) =
        await probe(const <String, String>{}, 'bin/client_probe.dart');

    expect(client['view'], isTrue);
    expect(client['delete'], isFalse);
    expect(client['note'], isTrue);
  });

  test('refuses to start when a route names an action nothing registered',
      () async {
    final (Map<String, Object?> r, _) =
        await probe(const <String, String>{'PROBE_MODE': 'unregistered'});

    expect(r['started'], isNull, reason: 'the server started: $r');
    expect('${r['refused']}', contains('DVApiKeyResource.viewAny'));
  });
}
