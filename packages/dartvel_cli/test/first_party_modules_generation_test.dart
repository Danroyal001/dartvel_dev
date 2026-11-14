// An application that mounts the three first-party modules, generated.
//
// The modules are the real ones in this repository's modules/ folder, so
// what is asserted is what an application gets: their secrets in no file
// of the generated client, their origins in the page policy, their start
// functions called, their carried operations and the store's webhook
// served.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/graph/module_mounts.dart';
import 'package:dartvel_cli/src/modules/first_party.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _page = '''
import 'package:flutter/widgets.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

@DVPage(title: 'Home')
Widget _home(BuildContext context) => const DVText('hi');
''';

/// Values that look like the real things, and are found nowhere else.
const Map<String, String> _secrets = <String, String>{
  'META_CONVERSIONS_API_TOKEN': 'EAABsecretMetaToken0123456789zzzz',
  'GA4_API_SECRET': 'gaSecretValue0123456789zzzz',
  'WOOCOMMERCE_CONSUMER_KEY': 'ck_secretconsumerkey0123456789zzzz',
  'WOOCOMMERCE_CONSUMER_SECRET': 'cs_secretconsumersecret0123456789zzzz',
  'WOOCOMMERCE_WEBHOOK_SECRET': 'whsecretvalue0123456789zzzz',
};

String _repository() {
  Directory dir = Directory.current;
  while (!Directory(p.join(dir.path, 'modules')).existsSync() ||
      !Directory(p.join(dir.path, 'packages', 'dartvel_cli')).existsSync()) {
    final Directory up = dir.parent;
    if (up.path == dir.path) fail('modules/ was not found above the tests');
    dir = up;
  }
  return dir.path;
}

Directory _application() {
  final Directory root =
      Directory.systemTemp.createTempSync('dartvel_first_party_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_page);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: shopfront
dartvel:
  envFiles: [.env]
  security:
    pageCsp: "default-src 'self'; script-src 'self' 'inline-scripts' 'wasm-unsafe-eval'; img-src 'self' data:; connect-src 'self'"
  modules:
    metaPixel:
      package: dartvel_meta_pixel
      backendPolicy: public
      config:
        pixelId: "1234567890"
    googleAnalytics:
      package: dartvel_google_analytics
      backendPolicy: public
      config:
        measurementId: G-ABC123XYZ9
    woocommerce:
      package: dartvel_woocommerce
      backendPolicy: public
      config:
        storeUrl: https://shop.example.com
''');
  File(p.join(root.path, '.env')).writeAsStringSync(<String>[
    'PUBLIC_SITE_NAME=Shopfront',
    for (final MapEntry<String, String> secret in _secrets.entries)
      '${secret.key}=${secret.value}',
  ].join('\n'));
  File(p.join(root.path, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        for (final DVFirstPartyModule module in dvFirstPartyModules)
          <String, Object?>{
            'name': module.package,
            'rootUri':
                Uri.directory(p.join(_repository(), 'modules', module.package))
                    .toString(),
            'packageUri': 'lib/',
          },
      ],
    }));
  return root;
}

Future<void> _generate(Directory root) async {
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'shopfront',
    buildId: 'b',
    modules: dvDiscoverModuleMounts(root.path),
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://example.com',
    apiBasePath: '/api',
    envFiles: const <String>['.env'],
    seoSiteName: 'app',
    seoTitle: 'app',
    seoDesc: 'app',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'none',
    durationMs: 200,
    curve: 'linear',
    normalizeTrailing: true,
    notFoundRedirect: '/',
    plugins: const <String>[],
    ota: false,
    dv: loadYaml(File(p.join(root.path, 'pubspec.yaml')).readAsStringSync())['dartvel']
        as YamlMap,
  );
  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'shopfront',
    buildId: 'b',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
}

void main() {
  test('all three are mounted, with nothing wrong', () {
    final List<DVModuleMount> mounts =
        dvDiscoverModuleMounts(_application().path);
    expect(mounts.map((DVModuleMount m) => m.id),
        <String>['googleAnalytics', 'metaPixel', 'woocommerce']);
    for (final DVModuleMount mount in mounts) {
      expect(mount.problems, isEmpty, reason: mount.id);
      expect(mount.mounted, isTrue);
      expect(mount.routes, isEmpty, reason: 'a first-party module has no pages');
    }
  });

  test('no secret is in any file of the generated client', () async {
    final Directory root = _application();
    await _generate(root);

    final List<File> client = Directory(p.join(root.path, 'lib'))
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(client.length, greaterThan(5));
    final String everything =
        client.map((File f) => f.readAsStringSync()).join('\n');
    for (final MapEntry<String, String> secret in _secrets.entries) {
      expect(everything, isNot(contains(secret.value)),
          reason: '${secret.key} was compiled into the client');
    }
    // env.g.dart scrambles the values it holds, so a scan for a value
    // would pass over one that was there. It names each variable it holds,
    // and it holds the public one and none of the secrets.
    final String env =
        File(p.join(root.path, 'lib', 'dartvel_client', 'env.g.dart'))
            .readAsStringSync();
    expect(env, contains('PUBLIC_SITE_NAME'));
    for (final String name in _secrets.keys) {
      expect(env, isNot(contains(name)),
          reason: '$name was compiled into the client');
    }
    // And the scan can see a value that is there: the public settings are.
    expect(everything, contains('1234567890'));
    expect(everything, contains('G-ABC123XYZ9'));
    expect(everything, contains('https://shop.example.com'));
  });

  test('no secret is written into the generated server either: it reads '
      'them from its environment when it runs', () async {
    final Directory root = _application();
    await _generate(root);
    final String server = Directory(p.join(root.path, '.dart_tool'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .map((File f) => f.readAsStringSync())
        .join('\n');
    for (final MapEntry<String, String> secret in _secrets.entries) {
      expect(server, isNot(contains(secret.value)), reason: secret.key);
    }
  });

  test('the page policy gains the modules\' origins and nothing looser',
      () async {
    final Directory root = _application();
    await _generate(root);
    final String routes =
        File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
            .readAsStringSync();
    final String policy = RegExp(
            r"const String\? dartvelPageContentSecurityPolicy = '(.*)';")
        .firstMatch(routes)!
        .group(1)!
        .replaceAll(r"\'", "'");
    final Map<String, List<String>> directives = <String, List<String>>{
      for (final String part in policy.split(';'))
        part.trim().split(' ').first: part.trim().split(' ').skip(1).toList(),
    };
    expect(
      directives['script-src'],
      <String>[
        "'self'",
        "'inline-scripts'",
        "'wasm-unsafe-eval'",
        'https://www.googletagmanager.com',
        'https://connect.facebook.net',
      ],
    );
    expect(directives['img-src'], containsAll(<String>[
      "'self'",
      'data:',
      'https://www.facebook.com',
      'https://www.googletagmanager.com',
      'https://*.google-analytics.com',
    ]));
    expect(directives['connect-src'], containsAll(<String>[
      "'self'",
      'https://www.facebook.com',
      'https://*.google-analytics.com',
      'https://*.google.com',
    ]));
    expect(policy, isNot(contains('unsafe-inline')));
    expect(directives['default-src'], <String>["'self'"]);
  });

  test('each module is started once it is registered, in a file the server '
      'can load', () async {
    final Directory root = _application();
    await _generate(root);
    final String registration = File(p.join(
            root.path, 'lib', 'dartvel_client', 'modules_data.g.dart'))
        .readAsStringSync();
    for (final String start in <String>[
      'startMetaPixel',
      'startGoogleAnalytics',
      'startWooCommerce',
    ]) {
      expect(registration, contains('.$start(dvModuleRegistry.register('));
    }
    expect(registration, isNot(contains('package:flutter/')));
    expect(registration, isNot(contains('dartvel_flutter')));
  });

  test('the application reaches each as its own surface', () async {
    final Directory root = _application();
    await _generate(root);
    final String accessors =
        File(p.join(root.path, 'lib', 'dartvel_client', 'modules.g.dart'))
            .readAsStringSync();
    expect(accessors, contains('MetaPixel get metaPixel => const MetaPixel();'));
    expect(accessors,
        contains('GoogleAnalytics get googleAnalytics => const GoogleAnalytics();'));
    expect(accessors,
        contains('WooCommerce get woocommerce => const WooCommerce();'));
  });

  test('the backend serves what clients carry to it, and the store\'s '
      'webhook', () async {
    final Directory root = _application();
    await _generate(root);
    final String routes =
        File(p.join(root.path, '.dart_tool', 'dartvel_backend_routes.g.dart'))
            .readAsStringSync();
    for (final String path in <String>[
      '/_dv/modules/metaPixel/collect',
      '/_dv/modules/googleAnalytics/collect',
      '/_dv/modules/woocommerce/products',
      '/_dv/modules/woocommerce/product',
      '/_dv/modules/woocommerce/startCheckout',
      '/_dv/modules/woocommerce/orderStatus',
    ]) {
      expect(routes, contains("cfg.apiBasePath + '$path'"), reason: path);
    }
    // Only what is carried: the typed API is not a route.
    expect(routes, isNot(contains('/_dv/modules/woocommerce/api')));
    expect(routes, isNot(contains('/_dv/modules/woocommerce/onOrderPaid')));
    // Outside the API base path, as the store was told.
    expect(routes, contains("'/_dartvel/woocommerce/webhook'"));
    expect(routes, isNot(contains("cfg.apiBasePath + '/_dartvel/woocommerce")));
    expect(routes, contains('wooCommerceWebhook(req)'));
  });
}
