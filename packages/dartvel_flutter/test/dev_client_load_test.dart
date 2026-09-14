// The dev client loading bundles from a paired `dartvel dev` server, over a
// real HTTP server and a real database.
//
// Every refusal here is a case that would otherwise look like success: a page
// renders, it is just the wrong page, or the right page on a shell that will
// crash when somebody taps the button calling a plugin it does not have.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show DVDiagnostics;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/dev_client.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentFor(String route, String text) {
  final document = DVPageDocument(route: route, title: text);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

// Node ids are generated, so a document built twice from the same text is
// two different contents. Built once per text, the same text is the same
// content -- which is what a developer undoing an edit produces.
final Map<String, Map<String, Object?>> _documents =
    <String, Map<String, Object?>>{};

Map<String, Object?> pagesSaying(String text) => <String, Object?>{
      'pages': <Object?>[
        _documents.putIfAbsent(text, () => documentFor('/about', text).toJson()),
      ],
    };

void main() {
  late SqliteDVDatabaseAdapter database;
  late HttpServer server;
  late DVDevClientSigner signer;
  late DVDevClientPairing pairing;

  const DVDevClientManifest shell = DVDevClientManifest(
    target: 'android',
    bindings: <String>['dartvel_flutter@0.4.0', 'plugin:jni'],
  );

  // What the server does next; each test sets it.
  late String Function(HttpRequest request) respond;
  int status = 200;
  final List<HttpRequest> seen = <HttpRequest>[];

  Future<String?> storedTitle() async {
    final document = await const DVPageStore().load('/about');
    return document?.title;
  }

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    seen.clear();
    status = 200;

    signer = DVDevClientSigner.generate();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    pairing = DVDevClientPairing(
      server: Uri.parse('http://${server.address.host}:${server.port}'),
      branch: 'feature/checkout',
      publicKey: signer.publicKey,
      token: DVDevClientPairing.newToken(),
    );
    server.listen((HttpRequest request) async {
      seen.add(request);
      request.response.statusCode = status;
      request.response.write(respond(request));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    database.close();
    DVPageStore.resetCache();
  });

  String sealed(
    String text, {
    String branch = 'feature/checkout',
    DVDevClientManifest requires = shell,
    int sequence = 1,
    DVDevClientSigner? by,
  }) =>
      (by ?? signer).seal(
        bundle: pagesSaying(text),
        channel: branch,
        requires: requires,
        sequence: sequence,
      );

  test('a sealed bundle from the paired server is applied', () async {
    respond = (_) => sealed('From the branch');
    final client = DVDevClient(pairing: pairing, shell: shell);

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.applied, reason: load.message);
    expect(await storedTitle(), 'From the branch');
    // It asked for this shell's target, with the token from the link.
    final request = seen.single;
    expect(request.uri.path, '/_dartvel/dev-client/bundle');
    expect(request.uri.queryParameters['target'], 'android');
    expect(request.headers.value('authorization'), 'Bearer ${pairing.token}');
  });

  test('a bundle sealed by another machine is not applied', () async {
    respond = (_) => sealed('Injected', by: DVDevClientSigner.generate());
    final client = DVDevClient(pairing: pairing, shell: shell);

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.rejected);
    expect(load.message, contains('signature'));
    expect(await storedTitle(), isNull);
  });

  test('an unsigned bundle is not applied', () async {
    respond = (_) => DVPageBundle(
          version: '1.0.0',
          pages: <DVPageDocument>[documentFor('/about', 'Unsigned')],
        ).encode();
    final client = DVDevClient(pairing: pairing, shell: shell);

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.rejected);
    expect(await storedTitle(), isNull);
  });

  test('a bundle needing a binding the shell lacks refuses with 002', () async {
    respond = (_) => sealed(
          'Needs a camera',
          requires: const DVDevClientManifest(
            target: 'android',
            bindings: <String>[
              'dartvel_flutter@0.4.0',
              'plugin:camera',
              'plugin:jni',
            ],
          ),
        );
    final client = DVDevClient(pairing: pairing, shell: shell);

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.incompatible);
    expect(load.code, 'DV-DEVCLIENT-002');
    expect(load.missing, <String>['plugin:camera']);
    expect(load.message, contains('plugin:camera'));
    expect(await storedTitle(), isNull,
        reason: 'refused before a single document reached the store');
  });

  test('a bundle that does not say what it needs is not applied', () async {
    respond = (_) => signer.seal(
          bundle: pagesSaying('No manifest'),
          channel: 'feature/checkout',
          sequence: 1,
        );
    final client = DVDevClient(pairing: pairing, shell: shell);

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.rejected);
    expect(await storedTitle(), isNull);
  });

  test('a bundle for another branch is not applied', () async {
    // The same server key serves whichever branch is checked out. A designer
    // who scanned the link for one branch must not be shown another.
    respond = (_) => sealed('Main', branch: 'main');
    final client = DVDevClient(pairing: pairing, shell: shell);

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.rejected);
    expect(load.message, contains('main'));
    expect(await storedTitle(), isNull);
  });

  test('every rebuild is applied, including a return to earlier content',
      () async {
    // The apply underneath is idempotent by version. Edit, edit back: the
    // third bundle has the first one's version, and treating it as already
    // applied would leave the second edit on screen.
    final client = DVDevClient(pairing: pairing, shell: shell);

    respond = (_) => sealed('One', sequence: 1);
    expect((await client.load()).outcome, DVDevClientOutcome.applied);
    expect(await storedTitle(), 'One');

    respond = (_) => sealed('Two', sequence: 2);
    expect((await client.load()).outcome, DVDevClientOutcome.applied);
    expect(await storedTitle(), 'Two');

    respond = (_) => sealed('One', sequence: 3);
    final back = await client.load();
    expect(back.outcome, DVDevClientOutcome.applied, reason: back.message);
    expect(await storedTitle(), 'One');
  });

  test('the same bundle fetched twice changes nothing', () async {
    final client = DVDevClient(pairing: pairing, shell: shell);
    final envelope = sealed('Once', sequence: 4);
    respond = (_) => envelope;

    expect((await client.load()).outcome, DVDevClientOutcome.applied);
    expect((await client.load()).outcome, DVDevClientOutcome.alreadyApplied);
  });

  test('an older bundle replayed after a newer one is refused', () async {
    final client = DVDevClient(pairing: pairing, shell: shell);

    respond = (_) => sealed('Newer', sequence: 9);
    expect((await client.load()).outcome, DVDevClientOutcome.applied);

    respond = (_) => sealed('Older', sequence: 3);
    final replay = await client.load();

    expect(replay.outcome, DVDevClientOutcome.rejected);
    expect(await storedTitle(), 'Newer');
  });

  test('a token the server refuses is reported as 001, not applied', () async {
    status = 401;
    respond = (_) => 'unauthorized';
    final client = DVDevClient(pairing: pairing, shell: shell);

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.unpaired);
    expect(load.code, 'DV-DEVCLIENT-001');
  });

  test('a server that is not there is reported as 001', () async {
    final gone = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = gone.port;
    await gone.close(force: true);
    final client = DVDevClient(
      pairing: DVDevClientPairing(
        server: Uri.parse('http://127.0.0.1:$port'),
        branch: 'feature/checkout',
        publicKey: signer.publicKey,
        token: pairing.token,
      ),
      shell: shell,
    );

    final load = await client.load();

    expect(load.outcome, DVDevClientOutcome.unreachable);
    expect(load.code, 'DV-DEVCLIENT-001');
    expect(load.message, contains('127.0.0.1:$port'));
    expect(DVDiagnostics.find(load.code!)?.level, 'warning');
  });

  test('each load is written to the log the dev menu shows', () async {
    respond = (_) => sealed('Logged');
    final client = DVDevClient(pairing: pairing, shell: shell);

    await client.load();

    expect(client.log, isNotEmpty);
    expect(client.log.last, contains('applied'));
  });

  group('OTA page bundles with a signing key', () {
    // The same envelope and the same check, reached through DV.Updates.
    late Uri endpoint;
    setUp(() {
      endpoint = Uri.parse('http://${server.address.host}:${server.port}/p');
    });

    test('a sealed bundle is applied', () async {
      respond = (_) => signer.seal(
            bundle: DVPageBundle(
              version: '2.0.0',
              pages: <DVPageDocument>[documentFor('/about', 'Signed OTA')],
            ).toJson(),
          );

      final result = await DV.Updates.applyPages(
        from: endpoint,
        signedBy: signer.publicKey,
      );

      expect(result.outcome, DVPageUpdateOutcome.applied);
      expect(result.version, '2.0.0');
      expect(await storedTitle(), 'Signed OTA');
    });

    test('an unsigned bundle is refused once a key is configured', () async {
      respond = (_) => DVPageBundle(
            version: '2.0.0',
            pages: <DVPageDocument>[documentFor('/about', 'Unsigned OTA')],
          ).encode();

      await expectLater(
        DV.Updates.applyPages(from: endpoint, signedBy: signer.publicKey),
        throwsA(isA<StateError>()),
      );
      expect(await storedTitle(), isNull);
    });

    test('a bundle sealed by another key is refused', () async {
      respond = (_) => DVDevClientSigner.generate().seal(
            bundle: DVPageBundle(
              version: '2.0.0',
              pages: <DVPageDocument>[documentFor('/about', 'Forged')],
            ).toJson(),
          );

      await expectLater(
        DV.Updates.applyPages(from: endpoint, signedBy: signer.publicKey),
        throwsA(isA<StateError>()),
      );
      expect(await storedTitle(), isNull);
    });
  });
}
