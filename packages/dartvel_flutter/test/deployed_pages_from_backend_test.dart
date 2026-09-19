// A phone, desktop or TV app gets the pages Studio deployed from its backend.
//
// Studio runs on the server and stores what it deploys there. A web app
// served by that server already read it; an app installed on a device read
// DV.Database on the device, where nothing is ever deployed, so the Deploy
// menu's "Apps get it the next time they open" was not true for any app.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late List<Map<String, Object?>> pages;
  late int requests;

  setUp(() async {
    pages = <Map<String, Object?>>[];
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      requests++;
      if (request.uri.path == '/_dartvel/pages') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(<String, Object?>{'pages': pages}));
      } else {
        request.response.statusCode = 404;
      }
      unawaited(request.response.close());
    });
    DV.registerRuntime(
      baseUrl: () => 'http://127.0.0.1:${server.port}',
      apiBasePath: () => '/api',
      api: (String path) => Uri.parse('http://127.0.0.1:${server.port}/api$path'),
    );
    DVPageStore.resetCache();
    DVDeployTarget.debugCurrent = DVDeployTarget.phones;
  });

  tearDown(() async {
    DVPageStore.fromBackend = false;
    DVDeployTarget.debugCurrent = null;
    DVPageStore.resetCache();
    await server.close(force: true);
  });

  Map<String, Object?> deployed(String route, {List<String>? targets}) {
    final DVPageDocument document = DVPageDocument(route: route, title: route);
    DVPageDocumentEditor(document)
        .insert(DVPageNode.text('Deployed $route'), parent: document.root.id);
    final Map<String, Object?> json = document.toJson();
    if (targets != null) json['targets'] = targets;
    return <String, Object?>{'route': route, 'document': json};
  }

  test('an app whose project runs Studio reads the deployed pages', () async {
    pages.add(deployed('/menu'));
    DVPageStore.fromBackend = true;

    await DVPageStore.prime();

    expect(DVPageStore.cached('/menu'), isNotNull);
    expect(requests, 1);
  });

  test('and leaves one deployed only to the website alone', () async {
    pages.add(deployed('/menu', targets: <String>['web']));
    DVPageStore.fromBackend = true;

    await DVPageStore.prime();

    expect(DVPageStore.cached('/menu'), isNull);
  });

  test('a backend that does not answer leaves the compiled pages', () async {
    await server.close(force: true);
    DVPageStore.fromBackend = true;

    await DVPageStore.prime();

    expect(DVPageStore.cached('/menu'), isNull);
  });

  test('an app whose project has no Studio never asks', () async {
    await DVPageStore.prime();

    expect(requests, 0);
  });
}
