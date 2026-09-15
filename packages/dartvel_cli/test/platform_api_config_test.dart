// dartvel.platformApi, read by `dartvel routes`.
//
// The runtime had DVApiScopes.validateAgainst and nothing called it at build:
// the CLI never read dartvel.platformApi, so a scope naming an action no
// policy defines built cleanly and shipped. Every call a partner made with it
// was then refused, and the failure read as the partner's bug. These run the
// generator the way `dartvel routes` does and assert on what it refused and
// on what the generated registry answers once compiled -- never on its text.
//
// The silent failures:
//  * a scope action matched by its action name alone, so Invoice.view passes
//    because some other resource has a view policy;
//  * a misspelt key under platformApi (`scope:`) dropped, leaving an
//    application with no scopes that believes it declared some;
//  * a failed build leaving half a client behind;
//  * a rate plan with no window read as "unlimited".
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _orderPolicy = '''
import 'package:dartvel_core/dartvel.dart';

class Order {
  const Order();
}

class Invoice {
  const Invoice();
}

@DVPolicy(Order)
class OrderPolicy {
  bool view(Object? user, Order order) => true;
  bool create(Object? user, Order order) => true;
}
''';

const String _probe = r'''
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';

import '../lib/dartvel_client/platform_api.g.dart' as gen;

void main() {
  final DVPlatformApiConfig? config = gen.dartvelPlatformApi;
  if (config == null) {
    print('PROBE null');
    return;
  }
  print('PROBE ${jsonEncode(<String, Object?>{
    'names': (config.scopes.names.toList()..sort()),
    'read': (config.scopes.actionsFor('orders:read').toList()..sort()),
    'write': (config.scopes.actionsFor('orders:write').toList()..sort()),
    'describeWrite': config.scopes.describe('orders:write'),
    'describeRead': config.scopes.describe('orders:read'),
    'plans': <String, Object?>{
      for (final MapEntry<String, DVApiRatePlan> e in config.ratePlans.entries)
        e.key: <int>[e.value.maxRequests, e.value.window.inSeconds],
    },
    'requireExpiry': config.requireExpiry,
    'oauth': config.oauth == null
        ? null
        : <int>[
            config.oauth!.accessTokenLifetime.inSeconds,
            config.oauth!.refreshTokenLifetime.inSeconds,
            config.oauth!.codeLifetime.inSeconds,
          ],
  })}');
}
''';

Directory _project(String platformApi) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_platform_api_');
  void write(String relative, String content) {
    File(p.join(dir.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: platform_api_probe
publish_to: none
environment:
  sdk: ^3.12.0
dartvel:
$platformApi
''');
  write('lib/policies/order_policy.dart', _orderPolicy);
  return dir;
}

void main() {
  final List<Directory> made = <Directory>[];
  tearDownAll(() {
    for (final Directory d in made) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  Future<void> refuses(String platformApi, List<String> words) async {
    final Directory dir = _project(platformApi);
    made.add(dir);
    await expectLater(
      routes.generate(root_: dir.path),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(<Matcher>[for (final String w in words) contains(w)]),
        ),
      ),
    );
    // Stopped before anything was written.
    expect(
      Directory(p.join(dir.path, 'lib', 'dartvel_client')).existsSync(),
      isFalse,
    );
  }

  group('the build stops on', () {
    test(
      'a scope naming an action no policy defines (DV-APIKEY-001)',
      () async {
        await refuses(
          '''
  platformApi:
    scopes:
      orders:read: [Order.view, Order.viewAny]
''',
          <String>['DV-APIKEY-001', 'orders:read', 'Order.viewAny'],
        );
      },
    );

    test('an action another resource has a policy for', () async {
      // OrderPolicy defines view. Invoice has no policy, so Invoice.view is
      // an action nothing will ever allow.
      await refuses(
        '''
  platformApi:
    scopes:
      invoices:read: [Invoice.view]
''',
        <String>['DV-APIKEY-001', 'invoices:read', 'Invoice.view'],
      );
    });

    test('an action that is not Resource.action', () async {
      await refuses(
        '''
  platformApi:
    scopes:
      orders:read: [view]
''',
        <String>['dartvel.platformApi', 'orders:read', 'view'],
      );
    });

    test('a key under platformApi nothing reads', () async {
      // Beside valid scopes, so the only thing wrong is the misspelling: a
      // dropped `rateplans:` is an application with no rate plans that
      // believes it declared some.
      await refuses(
        '''
  platformApi:
    scopes:
      orders:read: [Order.view]
    rateplans:
      standard: { maxRequests: 100, window: 1m }
''',
        <String>['dartvel.platformApi.rateplans', 'not a platform API setting'],
      );
    });

    test('a rate plan with no window', () async {
      await refuses(
        '''
  platformApi:
    scopes:
      orders:read: [Order.view]
    ratePlans:
      standard: { maxRequests: 100 }
''',
        <String>['dartvel.platformApi.ratePlans', 'standard', 'window'],
      );
    });
  });

  Future<Object?> probe(Directory dir) async {
    File(p.join(dir.path, 'bin', 'probe.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_probe);
    final Uri cli = (await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/src/generators/routes_generator.dart'),
    ))!;
    final String cliRoot = p.dirname(
      p.dirname(p.dirname(p.dirname(cli.toFilePath()))),
    );
    final ProcessResult result =
        await Process.run(Platform.resolvedExecutable, <String>[
          '--packages=${p.join(cliRoot, '.dart_tool', 'package_config.json')}',
          p.join(dir.path, 'bin', 'probe.dart'),
        ]).timeout(const Duration(minutes: 3));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String l) => l.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run:\n${result.stdout}\n${result.stderr}');
    }
    final String value = line.substring('PROBE '.length);
    return value == 'null' ? null : jsonDecode(value);
  }

  test('the registry is generated and answers as declared', () async {
    final Directory dir = _project('''
  platformApi:
    scopes:
      orders:read: [Order.view]
      orders:write:
        actions: [Order.create]
        description: Create orders on your behalf
    ratePlans:
      standard: { maxRequests: 100, window: 1m }
    requireExpiry: true
    oauth:
      accessTokenLifetime: 15m
      refreshTokenLifetime: 7d
''');
    made.add(dir);
    await routes.generate(root_: dir.path);

    final Object? r = await probe(dir);
    expect(r, <String, Object?>{
      'names': <String>['orders:read', 'orders:write'],
      'read': <String>['Order.view'],
      'write': <String>['Order.create'],
      'describeWrite': 'Create orders on your behalf',
      'describeRead': 'orders:read',
      'plans': <String, Object?>{
        'standard': <int>[100, 60],
      },
      'requireExpiry': true,
      'oauth': <int>[900, 604800, 60],
    });
  });

  test('a project that declares no platform API has no registry', () async {
    final Directory dir = _project('  backendPort: 8089');
    made.add(dir);
    await routes.generate(root_: dir.path);
    expect(await probe(dir), isNull);
  });
}
