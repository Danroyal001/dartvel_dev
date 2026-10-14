import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Object? body,
  Map<String, String>? headers,
}) =>
    Request(
      method: method,
      url: Uri.parse(
          'http://127.0.0.1${path.startsWith('/') ? '' : '/'}$path'),
      headers: Headers(<String, String>{
        if (body != null) 'content-type': 'application/json',
        'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
        ...?headers,
      }),
      bodyStream: body == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    );

Future<String> _text(Response response) async =>
    utf8.decode(await response.body!.bytes());

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(await _text(response)) as Map).cast<String, Object?>();

void main() {
  group('DVStudioMenuItem & DVStudioMenu models', () {
    test('serializes and deserializes cleanly', () {
      const DVStudioMenuItem child = DVStudioMenuItem(
        id: 'child-1',
        label: 'Docs',
        url: '/docs',
        target: '_self',
      );
      final DVStudioMenuItem parent = DVStudioMenuItem(
        id: 'parent-1',
        label: 'Resources',
        url: '#',
        target: '_self',
        children: <DVStudioMenuItem>[child],
      );

      final Map<String, Object?> json = parent.toJson();
      expect(json['id'], 'parent-1');
      expect(json['label'], 'Resources');
      expect((json['children'] as List).length, 1);

      final DVStudioMenuItem restored = DVStudioMenuItem.fromJson(json);
      expect(restored.id, 'parent-1');
      expect(restored.children.first.id, 'child-1');
      expect(restored.children.first.label, 'Docs');
      expect(restored.children.first.url, '/docs');
    });

    test('default menus provide primary and footer navigation', () {
      final List<DVStudioMenu> defaults = dvStudioDefaultMenus();
      expect(defaults.length, greaterThanOrEqualTo(2));
      final DVStudioMenu primary =
          defaults.firstWhere((DVStudioMenu m) => m.id == 'primary-menu');
      expect(primary.name, 'Primary Navigation');
      expect(primary.location, 'header');
      expect(primary.items, isNotEmpty);
      expect(primary.items.first.label, 'Home');
      expect(primary.items.first.url, '/');

      final DVStudioMenu footer =
          defaults.firstWhere((DVStudioMenu m) => m.id == 'footer-menu');
      expect(footer.name, 'Footer Links');
      expect(footer.location, 'footer');
    });
  });

  group('DVStudioApi menus endpoints', () {
    late MemoryDVDatabaseAdapter database;
    late DVStudioApi api;

    setUp(() {
      database = MemoryDVDatabaseAdapter();
      api = DVStudioApi(database: database);
    });

    test('GET api/menus returns default menus and location list', () async {
      final Response response =
          await api.respond(_request('GET', 'api/menus'), 'menus');
      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);
      expect(body['menus'], isA<List>());
      expect(body['locations'], isA<List>());
      final List<Object?> menus = body['menus']! as List;
      expect(menus.length, greaterThanOrEqualTo(2));
    });

    test('GET api/menus with id returns single menu', () async {
      final Response response = await api.respond(
        _request('GET', 'api/menus?id=primary-menu'),
        'menus',
      );
      expect(response.status, 200);
      final Map<String, Object?> menu = await _json(response);
      expect(menu['id'], 'primary-menu');
      expect(menu['name'], 'Primary Navigation');
    });

    test('GET api/menus with non-existent id returns 404', () async {
      final Response response = await api.respond(
        _request('GET', 'api/menus?id=does-not-exist'),
        'menus',
      );
      expect(response.status, 404);
    });

    test('POST api/menus creates a new menu and logs activity', () async {
      final Response response = await api.respond(
        _request(
          'POST',
          'api/menus',
          body: <String, Object?>{
            'id': 'sidebar-menu',
            'name': 'Sidebar Navigation',
            'location': 'sidebar',
            'items': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'sb-1',
                'label': 'Dashboard',
                'url': '/dashboard',
                'target': '_self',
              },
            ],
          },
        ),
        'menus',
      );
      expect(response.status, 200);
      final Map<String, Object?> created = await _json(response);
      expect(created['id'], 'sidebar-menu');
      expect(created['name'], 'Sidebar Navigation');
      expect(created['location'], 'sidebar');

      // Verify it appears in listing
      final Response listRes =
          await api.respond(_request('GET', 'api/menus'), 'menus');
      final Map<String, Object?> listBody = await _json(listRes);
      final List<Object?> all = listBody['menus']! as List;
      expect(
          all.any((Object? m) => (m as Map)['id'] == 'sidebar-menu'), isTrue);

      // Verify activity note
      final DVStudioOverview overview = await api.overview();
      expect(
        overview.recent.any((DVStudioActivity a) =>
            a.screen == 'menus' &&
            a.label == 'Menu updated: Sidebar Navigation'),
        isTrue,
      );
    });

    test('POST api/menus refuses menu without id or name', () async {
      final Response res1 = await api.respond(
        _request(
          'POST',
          'api/menus',
          body: <String, Object?>{'id': '', 'name': 'Unnamed'},
        ),
        'menus',
      );
      expect(res1.status, 400);

      final Response res2 = await api.respond(
        _request(
          'POST',
          'api/menus',
          body: <String, Object?>{'id': 'test', 'name': ''},
        ),
        'menus',
      );
      expect(res2.status, 400);
    });

    test('DELETE api/menus deletes menu and logs activity', () async {
      // First create one
      await api.respond(
        _request(
          'POST',
          'api/menus',
          body: <String, Object?>{
            'id': 'to-delete',
            'name': 'To Delete',
            'location': 'custom',
            'items': const <Object?>[],
          },
        ),
        'menus',
      );

      final Response delRes = await api.respond(
        _request('DELETE', 'api/menus?id=to-delete'),
        'menus',
      );
      expect(delRes.status, 200);

      // Verify gone
      final Response getRes = await api.respond(
        _request('GET', 'api/menus?id=to-delete'),
        'menus',
      );
      expect(getRes.status, 404);

      // Verify activity note
      final DVStudioOverview overview = await api.overview();
      expect(
        overview.recent.any((DVStudioActivity a) =>
            a.screen == 'menus' && a.label == 'Menu deleted: to-delete'),
        isTrue,
      );
    });
  });

  group('menus documents & aliases', () {
    test('dvStudioScreens includes menus', () {
      final DVStudioScreenSpec? spec = dvStudioScreenFor('menus');
      expect(spec, isNotNull);
      expect(spec!.id, 'menus');
      expect(spec.label, 'Menus');
    });

    test('aliases resolve navigation and nav to menus', () {
      for (final String alias in <String>['navigation', 'nav']) {
        final DVStudioScreenSpec? spec = dvStudioScreenFor(alias);
        expect(spec, isNotNull);
        expect(spec!.id, 'menus');
      }
    });

    test('menus screen document renders heading and summary', () {
      final DVStudioTarget? target =
          dvStudioTargetFor('/__studio/menus', mount: '/__studio');
      expect(target, isNotNull);
      final DVStudioDocument doc = dvStudioDocumentFor(
        target!,
        mount: '/__studio',
        data: const DVStudioProjectData(),
      );
      expect(doc.heading, 'Menus');
      expect(doc.html, contains('<h1>Menus</h1>'));
      expect(doc.html, contains('Configure site navigation'));
    });

    test('serves object document /__studio/menus/primary-menu', () {
      final DVStudioTarget? target =
          dvStudioTargetFor('/__studio/menus/primary-menu', mount: '/__studio');
      expect(target, isNotNull);
      final DVStudioDocument doc = dvStudioDocumentFor(
        target!,
        mount: '/__studio',
        data: const DVStudioProjectData(),
      );
      expect(doc.heading, 'primary-menu');
      expect(doc.html, contains('<h1>primary-menu</h1>'));
    });
  });
}
