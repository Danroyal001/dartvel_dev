// Studio and the project's files, kept in step during development.
//
// On a development server Studio writes every page, component and set of
// shortcuts it saves to the project -- studio/pages/<route>.json and so on,
// the files code uses -- so a commit carries them and the next build ships
// them. A file changed in code is read back into Studio. And when both
// changed, Studio does not write over the code's version: it says so, with
// both, and writes only when told to.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(String method, String path, {Object? body}) => Request(
      method: method,
      url: Uri.parse('http://localhost/__studio/api/$path'),
      headers: Headers(<String, String>{
        'x-dartvel-csrf-token': 'test-token-test-token-test-token',
        if (body != null) 'content-type': 'application/json',
      }),
      bodyStream: body == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    );

Map<String, Object?> _page(String route, String text) => <String, Object?>{
      'route': route,
      'title': route,
      'root': <String, Object?>{
        'id': 'root',
        'type': 'box',
        'children': <Object?>[
          <String, Object?>{
            'id': 't',
            'type': 'text',
            'properties': <String, Object?>{'text': text},
          },
        ],
      },
    };

void main() {
  late Directory project;
  late MemoryDVDatabaseAdapter database;
  late DVStudioApi api;

  setUp(() {
    project = Directory.systemTemp.createTempSync('dv_studio_sources');
    database = MemoryDVDatabaseAdapter();
    api = DVStudioApi(database: database, sourceRoot: project.path);
  });

  tearDown(() => project.deleteSync(recursive: true));

  Future<Response> call(String method, String path, {Object? body}) =>
      api.respond(_request(method, path, body: body), path.split('?').first);

  File file(String relative) => File('${project.path}/$relative');

  Future<Map<String, Object?>> json(Response response) async =>
      (jsonDecode(utf8.decode(await response.body!.bytes())) as Map)
          .cast<String, Object?>();

  test('where each document is kept in the project', () {
    expect(dvStudioSourcePath('/'), 'studio/pages/index.json');
    expect(dvStudioSourcePath('/docs/intro'), 'studio/pages/docs/intro.json');
    expect(dvStudioSourcePath('/_dartvel/components/PriceCard'),
        'studio/components/PriceCard.json');
    expect(dvStudioSourcePath('/_dartvel/shortcuts'), 'studio/shortcuts.json');
    for (final String route in <String>[
      '/', '/docs/intro', '/_dartvel/components/PriceCard', '/_dartvel/shortcuts',
    ]) {
      expect(dvStudioSourceRoute(dvStudioSourcePath(route)!), route);
    }
    expect(dvStudioSourcePath('/../escape'), isNull,
        reason: 'nothing is written outside studio/');
  });

  test('saving a page writes it to the project, and deleting it deletes '
      'the file', () async {
    expect((await call('PUT', 'pages', body: <String, Object?>{
      'document': _page('/landing', 'Hello'),
    })).status, 200);
    final File written = file('studio/pages/landing.json');
    expect(written.existsSync(), isTrue);
    expect((jsonDecode(written.readAsStringSync()) as Map)['route'], '/landing');

    expect((await call('DELETE', 'pages?route=%2Flanding')).status, 200);
    expect(written.existsSync(), isFalse);
  });

  test('a file changed in code is read back into Studio', () async {
    await call('PUT', 'pages', body: <String, Object?>{
      'document': _page('/landing', 'Hello'),
    });
    file('studio/pages/landing.json')
        .writeAsStringSync(jsonEncode(_page('/landing', 'Edited in code')));
    file('studio/pages/about.json').createSync(recursive: true);
    file('studio/pages/about.json')
        .writeAsStringSync(jsonEncode(_page('/about', 'New in code')));

    final Map<String, Object?> body = await json(await call('GET', 'pages'));
    final String listed = jsonEncode(body['pages']);
    expect(listed, contains('Edited in code'));
    expect(listed, contains('New in code'));
  });

  test('when the file changed in code since Studio wrote it, Studio does not '
      'write over it: it answers with both, and writes when told to',
      () async {
    await call('PUT', 'pages', body: <String, Object?>{
      'document': _page('/landing', 'Hello'),
    });
    final File source = file('studio/pages/landing.json');
    source.writeAsStringSync(jsonEncode(_page('/landing', 'Edited in code')));

    final Response refused = await call('PUT', 'pages', body: <String, Object?>{
      'document': _page('/landing', 'Edited in Studio'),
    });
    expect(refused.status, 409);
    final Map<String, Object?> conflict = await json(refused);
    expect(conflict['error'], 'changed_in_code');
    expect(conflict['path'], 'studio/pages/landing.json');
    expect(jsonEncode(conflict['inCode']), contains('Edited in code'));
    expect(source.readAsStringSync(), contains('Edited in code'),
        reason: 'the code\'s version is untouched');

    final Response forced = await call('PUT', 'pages', body: <String, Object?>{
      'document': _page('/landing', 'Edited in Studio'),
      'force': true,
    });
    expect(forced.status, 200);
    expect(source.readAsStringSync(), contains('Edited in Studio'));
  });

  test('a deployed server has no project to write to, and writes none',
      () async {
    final DVStudioApi deployed = DVStudioApi(database: MemoryDVDatabaseAdapter());
    final Response saved = await deployed.respond(
      _request('PUT', 'pages', body: <String, Object?>{
        'document': _page('/landing', 'Hello'),
      }),
      'pages',
    );
    expect(saved.status, 200);
    expect(Directory('${project.path}/studio').existsSync(), isFalse);
  });
}
