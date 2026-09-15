// What `dartvel routes` refuses about a route's declared policy.
//
// A route declaring @DVBackendFunction(policy: 'Invoice.view') where no
// @DVPolicy class defines view on Invoice is a guard nobody wrote. At run time
// it can only refuse everybody or -- with an application decide that says yes
// -- nobody, and neither says out loud that the policy does not exist. The
// build knows every policy class the server will register, so it says so there.
//
// A policy class the server cannot load is the other half. The generated
// server imports what it registers, and a file that reaches Flutter cannot be
// compiled into a process with no dart:ui; registering it anyway is the bug
// that made the server stop registering policies at all. So such a class is
// registered in the client only, and a route that needs it stops the build.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Generates a project whose lib is [lib] and whose embedded module `store`
/// has [moduleLib]; returns its root.
Future<Directory> generate({
  Map<String, String> lib = const <String, String>{},
  Map<String, String> moduleLib = const <String, String>{},
}) async {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_policy_generation_');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  void write(String relative, String content) {
    File(p.join(root.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: shopfront
dartvel:
  modules:
    store:
      source: { path: modules/store }
      mount: /store
      deployment: embedded
''');
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  lib.forEach((String name, String source) => write('lib/$name', source));
  write('modules/store/pubspec.yaml', '''
name: store
dartvel:
  module:
    id: store
    version: 1.0.0
''');
  moduleLib.forEach(
      (String name, String source) => write('modules/store/lib/$name', source));

  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'shopfront',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
  return root;
}

String route(String policy) => '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: '$policy')
Future<String> _guarded() async => 'ok';
''';

const String orderPolicy = '''
import 'package:dartvel_core/dartvel.dart';

class Order {}

@DVPolicy(Order)
class OrderPolicy {
  bool view(Object? user, Order? order) => true;
}
''';

/// The same policy, written the way application code is told to reach its
/// models: through the generated barrel, which exports Flutter.
const String orderPolicyThroughBarrel = '''
import 'package:shopfront/dartvel_client/dartvel_client.dart';

@DVPolicy(Order)
class OrderPolicy {
  bool view(Object? user, Order? order) => true;
}
''';

String generated(Directory root, String name) =>
    File(p.join(root.path, 'lib', 'dartvel_client', name)).readAsStringSync();

void main() {
  test('a route naming an action no policy class defines stops the build',
      () async {
    await expectLater(
      generate(lib: <String, String>{
        'policies/order_policy.dart': orderPolicy,
        'backend/functions/invoices.get.dart': route('Invoice.view'),
      }),
      throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
          allOf(contains('Invoice.view'), contains('invoices.get.dart')))),
    );
  });

  test('an action on the right resource is not satisfied by another action',
      () async {
    await expectLater(
      generate(lib: <String, String>{
        'policies/order_policy.dart': orderPolicy,
        'backend/functions/orders.delete.dart': route('Order.delete'),
      }),
      throwsA(isA<StateError>().having(
          (StateError e) => e.message, 'message', contains('Order.delete'))),
    );
  });

  test('a route whose policy only the client can load stops the build',
      () async {
    await expectLater(
      generate(lib: <String, String>{
        'policies/order_policy.dart': orderPolicyThroughBarrel,
        'backend/functions/orders.get.dart': route('Order.view'),
      }),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        allOf(contains('Order.view'), contains('policies/order_policy.dart'),
            contains('Flutter')),
      )),
    );
  });

  test('a policy class in a merged module satisfies the module\'s route',
      () async {
    final Directory root = await generate(moduleLib: <String, String>{
      'policies/note_policy.dart': '''
import 'package:dartvel_core/dartvel.dart';

class Note {}

@DVPolicy(Note)
class NotePolicy {
  bool view(Object? user, Note? note) => true;
}
''',
      'backend/functions/notes.get.dart': route('Note.view'),
    });

    expect(generated(root, 'backend_policies.g.dart'),
        contains('package:store/policies/note_policy.dart'));
  });

  test('a framework resource is left to the application and checked at start',
      () async {
    // The build cannot see a hand registration, so it does not refuse one; the
    // server refuses to start instead, which the backend test holds to.
    await generate(lib: <String, String>{
      'backend/functions/keys.get.dart': route('DVApiKeyResource.viewAny'),
    });
  });

  test('a policy only the client can load is kept out of the server', () async {
    final Directory root = await generate(lib: <String, String>{
      'policies/order_policy.dart': orderPolicyThroughBarrel,
    });

    expect(generated(root, 'policies.g.dart'), contains('OrderPolicy'));
    expect(generated(root, 'backend_policies.g.dart'),
        isNot(contains('OrderPolicy')));
  });

  test('a policy method may take its resource as nullable', () async {
    // A route has no order to hand the policy, so answering for one means
    // taking Order?. Refusing that as a different type would leave no way to
    // write a policy a route can ask.
    final Directory root = await generate(lib: <String, String>{
      'policies/order_policy.dart': orderPolicy,
      'backend/functions/orders.get.dart': route('Order.view'),
    });

    expect(generated(root, 'backend_policies.g.dart'), contains('OrderPolicy'));
  });
}
