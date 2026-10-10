// The generated backend's purchase endpoints, served and called.
//
// `dartvel.purchases` is what makes the generated server verify receipts and
// accept the stores' notifications. This generates a real backend, starts it,
// and calls it the way a device and a store do, asserting on what the server
// answered and what it granted -- never on the generated text. The silent
// failures:
//
//  * a receipt verified for a request with no session, granting to nobody
//    in particular;
//  * a forged store notification accepted because the route forgot to hand
//    the headers to the adapter;
//  * the endpoints served by an application that sells nothing.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _probe = r'''
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;

import '../.dart_tool/dartvel_backend_routes.g.dart' as gen;

const Entitlement pro = Entitlement('pro');

Future<int> call(int port, String method, String path,
    {String? body, Map<String, String> headers = const <String, String>{}}) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request = await client.openUrl(
        method, Uri.parse('http://127.0.0.1:$port/api$path'));
    request.headers.contentType = ContentType.json;
    headers.forEach(request.headers.set);
    if (body != null) request.add(utf8.encode(body));
    final HttpClientResponse response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  const DVDatabase().configure(MemoryDVDatabaseAdapter());
  final DateTime now = DateTime.now().toUtc();
  final DVFakeStoreAdapter play = DVFakeStoreAdapter(DVStore.play,
      signingKey: 'probe', acknowledgementWindow: const Duration(days: 3));
  final DVMemoryPurchaseLedger ledger = DVMemoryPurchaseLedger();
  final DVPurchases purchases = DVPurchases(
    products: const <DVPurchaseProduct>[
      DVPurchaseProduct('pro_monthly',
          billable: DVBillable.digital(play: 'pro'),
          entitlements: <Entitlement>{pro}),
    ],
    stores: <DVStoreAdapter>[play],
    ledger: ledger,
  );
  DVPurchases.configure(purchases);
  // A purchase the server already granted, so a notification has something
  // to revoke.
  play.issue('r1', DVStoreTransaction(
    store: DVStore.play,
    originalTransactionId: 'tok_1',
    transactionId: 'GPA.1',
    storeProductId: 'pro',
    purchasedAt: now,
    signedAt: now,
    expiresAt: now.add(const Duration(days: 30)),
  ));
  await purchases.verifyPurchase(DVStore.play, 'r1', customer: 'alice');

  final dynamic handle = await gen.startBackend(host: '127.0.0.1', port: 0);
  final int port = handle.port as int;
  final Map<String, Object?> out = <String, Object?>{};
  try {
    out['verifyWithoutSession'] = await call(port, 'POST',
        DVHttpPurchaseBackend.verifyPath,
        body: jsonEncode(<String, Object?>{'store': 'play', 'receipts': <String>['r1']}),
        headers: <String, String>{'authorization': 'Bearer dvs_not_a_session'});
    out['entitlementsWithoutSession'] =
        await call(port, 'GET', DVHttpPurchaseBackend.entitlementsPath);
    out['forged'] = await call(port, 'POST',
        DVHttpPurchaseBackend.playNotificationsPath,
        body: '{"message":{}}');
    final DVSignedStoreNotification signed = play.sign(DVStoreNotification(
      notificationId: 'm1',
      type: 'SUBSCRIPTION_REVOKED',
      signedAt: now.add(const Duration(minutes: 1)),
      transaction: DVStoreTransaction(
        store: DVStore.play,
        originalTransactionId: 'tok_1',
        transactionId: 'GPA.1',
        storeProductId: 'pro',
        purchasedAt: now,
        signedAt: now.add(const Duration(minutes: 1)),
        expiresAt: now.add(const Duration(days: 30)),
        revokedAt: now.add(const Duration(minutes: 1)),
        acknowledged: true,
      ),
    ));
    out['signed'] = await call(port, 'POST',
        DVHttpPurchaseBackend.playNotificationsPath,
        body: signed.body, headers: signed.headers);
    out['stillEntitled'] = await purchases.entitled('alice', pro);
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
      p.dirname(p.dirname(p.dirname(p.dirname(cli.toFilePath())))));
}

Future<Directory> backendProject(String packages, String purchases) async {
  final Directory project =
      Directory.systemTemp.createTempSync('dv_purchases_backend_');
  void write(String relative, String content) {
    File(p.join(project.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  write('pubspec.yaml', '''
name: purchases_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
dartvel:
  backendHost: 127.0.0.1
$purchases
''');
  write('pubspec_overrides.yaml', '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(packages, 'dartvel_core')}
  dartvel_shelf:
    path: ${p.join(packages, 'dartvel_shelf')}
''');
  write('lib/backend/functions/ping.get.dart', '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _ping() async => 'pong';
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
        'dartvel routes failed:\n${generated.stdout}\n${generated.stderr}');
  }
  final ProcessResult resolved = await Process.run(
    Platform.resolvedExecutable,
    <String>['pub', 'get'],
    workingDirectory: project.path,
  );
  if (resolved.exitCode != 0) {
    throw StateError('dart pub get failed:\n${resolved.stderr}');
  }
  return project;
}

void main() {
  late Directory selling;
  late Directory notSelling;

  setUpAll(() async {
    final String packages = await packagesDirectory();
    selling = await backendProject(packages, '  purchases: {}');
    notSelling = await backendProject(packages, '  backendPort: 8089');
  });

  tearDownAll(() {
    for (final Directory project in <Directory>[selling, notSelling]) {
      if (project.existsSync()) project.deleteSync(recursive: true);
    }
  });

  Future<Map<String, Object?>> probe(Directory project) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'bin/probe.dart'],
      workingDirectory: project.path,
    ).timeout(const Duration(minutes: 3));
    final String? line = const LineSplitter()
        .convert('${result.stdout}')
        .where((String candidate) => candidate.startsWith('PROBE '))
        .firstOrNull;
    if (result.exitCode != 0 || line == null) {
      fail('the probe did not run (exit ${result.exitCode}):\n'
          '${result.stdout}\n${result.stderr}');
    }
    return jsonDecode(line.substring('PROBE '.length)) as Map<String, Object?>;
  }

  test('device calls need a session; notifications need the store signature',
      () async {
    final Map<String, Object?> answers = await probe(selling);

    expect(answers['verifyWithoutSession'], anyOf(401, 403),
        reason: 'a session that does not authenticate is refused');
    expect(answers['entitlementsWithoutSession'], 401);
    expect(answers['forged'], 400);
    expect(answers['signed'], 200);
    expect(answers['stillEntitled'], isFalse,
        reason: 'the signed revocation reached the ledger');
  });

  test('an application that declares no purchases serves no endpoint',
      () async {
    final Map<String, Object?> answers = await probe(notSelling);

    expect(answers['entitlementsWithoutSession'], 404);
    expect(answers['forged'], 404);
    expect(answers['signed'], 404);
    expect(answers['stillEntitled'], isTrue);
  });
}
