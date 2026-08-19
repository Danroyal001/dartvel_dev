// The path from a published edit to an installed app.
//
// The bundle machinery and the override machinery were both tested, but
// nothing connected them: DVPageBundle appeared nowhere outside its own file,
// so an application had to fetch and apply bundles by hand. These tests cover
// the join — over a real HTTP server and a real database, because the failure
// modes that matter (a 404, a redelivered patch, a pinned device) are about
// what actually comes back over the wire.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument documentFor(String route, String text) {
  final document = DVPageDocument(route: route, title: text);
  DVPageDocumentEditor(document)
      .insert(DVPageNode.text(text), parent: document.root.id);
  return document;
}

void main() {
  late SqliteDVDatabaseAdapter database;
  late HttpServer server;
  late Uri endpoint;

  // What the server returns next; each test sets it.
  int status = 200;
  String body = '';

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    DV.Updates.unlockVersion();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://${server.address.host}:${server.port}/pages');
    server.listen((HttpRequest request) async {
      request.response.statusCode = status;
      request.response.write(body);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    database.close();
    DVPageStore.resetCache();
    DV.Updates.unlockVersion();
  });

  test('a fetched bundle is applied and its pages go live', () async {
    status = 200;
    body = DVPageBundle(
      version: '1.4.0',
      pages: <DVPageDocument>[documentFor('/about', 'Edited in Studio')],
    ).encode();

    final result = await DV.Updates.applyPages(from: endpoint);

    expect(result.outcome, DVPageUpdateOutcome.applied);
    expect(result.version, '1.4.0');
    expect(result.pages, 1);
    expect(result.changedAnything, isTrue);

    const store = DVPageStore();
    final stored = await store.load('/about');
    expect(stored, isNotNull,
        reason: 'the document must reach the store the renderer reads');
    expect(await DV.Updates.appliedPageVersions(), <String>['1.4.0']);
  });

  test('a redelivered bundle changes nothing', () async {
    // An OTA patch can arrive twice. Re-applying would silently undo any edit
    // published since, so the second delivery must be inert.
    status = 200;
    body = DVPageBundle(
      version: '1.4.0',
      pages: <DVPageDocument>[documentFor('/about', 'First')],
    ).encode();
    await DV.Updates.applyPages(from: endpoint);

    body = DVPageBundle(
      version: '1.4.0',
      pages: <DVPageDocument>[documentFor('/about', 'Should not overwrite')],
    ).encode();
    final second = await DV.Updates.applyPages(from: endpoint);

    expect(second.outcome, DVPageUpdateOutcome.alreadyApplied);
    expect(second.changedAnything, isFalse);
    final stored = await const DVPageStore().load('/about');
    expect(stored!.toJson().toString(), contains('First'));
  });

  test('a version lock declines a bundle from another release', () async {
    status = 200;
    body = DVPageBundle(
      version: '2.0.0',
      pages: <DVPageDocument>[documentFor('/about', 'Newer')],
    ).encode();
    DV.Updates.lockVersion('1.4.0');

    final result = await DV.Updates.applyPages(from: endpoint);

    expect(result.outcome, DVPageUpdateOutcome.declined);
    expect(await const DVPageStore().load('/about'), isNull,
        reason: 'a pinned device must not take content from another release');
    expect(await DV.Updates.appliedPageVersions(), isEmpty);
  });

  test('the pinned version is still accepted under a lock', () async {
    status = 200;
    body = DVPageBundle(
      version: '1.4.0',
      pages: <DVPageDocument>[documentFor('/about', 'Pinned release')],
    ).encode();
    DV.Updates.lockVersion('1.4.0');

    final result = await DV.Updates.applyPages(from: endpoint);

    expect(result.outcome, DVPageUpdateOutcome.applied);
  });

  test('no bundle to serve is not a failure', () async {
    status = 404;
    body = 'not found';

    final result = await DV.Updates.applyPages(from: endpoint);

    expect(result.outcome, DVPageUpdateOutcome.none);
    expect(result.changedAnything, isFalse);
  });

  test('a server error is reported rather than swallowed', () async {
    status = 500;
    body = 'boom';

    await expectLater(
      DV.Updates.applyPages(from: endpoint),
      throwsA(isA<StateError>()),
    );
  });

  test('a response that is not a bundle names the source', () async {
    status = 200;
    body = jsonEncode(<String, Object?>{'unexpected': true});

    await expectLater(
      DV.Updates.applyPages(from: endpoint),
      throwsA(isA<Object>()),
    );
  });

  test('removedRoutes withdraws an edit through the update path', () async {
    status = 200;
    body = DVPageBundle(
      version: '1.0.0',
      pages: <DVPageDocument>[documentFor('/about', 'Shipped by mistake')],
    ).encode();
    await DV.Updates.applyPages(from: endpoint);
    expect(await const DVPageStore().load('/about'), isNotNull);

    body = const DVPageBundle(
      version: '1.0.1',
      removedRoutes: const <String>['/about'],
    ).encode();
    final withdrawal = await DV.Updates.applyPages(from: endpoint);

    expect(withdrawal.outcome, DVPageUpdateOutcome.applied);
    expect(withdrawal.removedRoutes, 1);
    expect(await const DVPageStore().load('/about'), isNull,
        reason: 'the compiled page must come back when the edit is withdrawn');
  });
}
