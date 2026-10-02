// Studio's pages and data models come from each project's own source.
//
// Nothing about a site is kept in a list: Studio's Pages and Site map list
// the routes the generator found in lib/pages, and its Data lists the models
// it found in lib/models, beside whatever was stored in Studio. Two projects
// that share nothing -- a site served by a web-server binary, and an app
// that runs on a phone -- each get their own, and a data model designed in
// Studio and written out to lib/models compiles back to the model Studio
// stored: the same table, key, fields, rules, indexes and access.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/dev_studio.dart' show dvDevStudioModels;
import 'package:dartvel_cli/src/commands/admin_command.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:dartvel_cli/src/generators/model_generator.dart';
import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

String _page(String name, String path) => '''
import 'package:dartvel_core/dartvel.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: '$name')
Widget _${name}Page(BuildContext context) => const SizedBox.shrink();
''';

/// A project on disk, with [files] under its root.
Future<Directory> _project(String name, Map<String, String> files) async {
  final Directory root = await Directory.systemTemp.createTemp('dv_$name');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('name: $name\n');
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  files.forEach((String path, String source) {
    File(p.join(root.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(source);
  });
  return root;
}

Future<void> _generate(Directory root, String name) async {
  await ModelGenerator.generate(
    root: root.path,
    pkgName: name,
    buildId: 'test-build',
  );
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: name,
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://api.example.test',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: name,
    seoTitle: name,
    seoDesc: name,
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'fade',
    durationMs: 200,
    curve: 'easeInOut',
    normalizeTrailing: true,
    notFoundRedirect: '',
    plugins: const <String>[],
    ota: false,
    dv: loadYaml('{}') as YamlMap,
  );
}

/// The paths `dartvelRouteManifest` lists in the generated router.
List<String> _manifest(Directory root) {
  final String router = File(
    p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
  ).readAsStringSync();
  final int at = router.indexOf('dartvelRouteManifest');
  final int end = router.indexOf('];', at);
  return <String>[
    for (final RegExpMatch m in RegExp(r"path: '([^']*)'")
        .allMatches(router.substring(at, end)))
      m.group(1)!,
  ];
}

/// The paths `dartvelPagePreview` builds a page for.
List<String> _previews(Directory root) {
  final String router = File(
    p.join(root.path, 'lib', 'dartvel_client', 'router.g.dart'),
  ).readAsStringSync();
  final int at = router.indexOf('Widget? dartvelPagePreview(String path');
  expect(at, isNot(-1), reason: 'no dartvelPagePreview');
  final int end = router.indexOf('_ => content', at);
  return <String>[
    for (final RegExpMatch m
        in RegExp(r"'([^']*)' =>").allMatches(router.substring(at, end)))
      m.group(1)!,
  ];
}

Request _get(String path) => Request(
  method: 'GET',
  url: Uri.parse('http://localhost$path'),
  headers: Headers(const <String, String>{}),
  bodyStream: const Stream<List<int>>.empty(),
);

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(utf8.decode(await response.body!.bytes())) as Map)
        .cast<String, Object?>();

void main() {
  test('a web-server site: Studio lists its compiled routes and its stored '
      'pages from the build\'s graph', () async {
    final Directory site = await _project('roastery_site', <String, String>{
      'lib/pages/index.dart': _page('home', '/'),
      'lib/pages/menu.dart': _page('menu', '/menu'),
      'lib/pages/blog/[slug].dart': _page('post', '/blog/:slug'),
    });
    final DartvelProjectGraph graph =
        await DartvelProjectGraph.build(root: site.path, pkgName: 'roastery_site');
    final Directory admin = Directory(p.join(site.path, 'build', '__admin'))
      ..createSync(recursive: true);
    File(p.join(admin.path, 'graph.json'))
        .writeAsStringSync(jsonEncode(graph.toJson()));

    final MemoryDVDatabaseAdapter database = MemoryDVDatabaseAdapter();
    final DVStudioApi api = DVStudioApi(database: database, root: admin.path);
    // One page published over a compiled one, one at a route of its own.
    for (final String route in <String>['/menu', '/landing']) {
      final Response saved = await api.respond(
        Request(
          method: 'PUT',
          url: Uri.parse('http://localhost/api/pages'),
          headers: Headers(const <String, String>{
            'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
          }),
          bodyStream: Stream<List<int>>.value(utf8.encode(jsonEncode(
            <String, Object?>{
              'document': <String, Object?>{
                'route': route,
                'root': <String, Object?>{'type': 'box'},
              },
            },
          ))),
        ),
        'pages',
      );
      expect(saved.status, 200);
    }
    final Response listed = await api.respond(_get('/api/site'), 'site');
    final Map<String, String> kinds = <String, String>{
      for (final Object? page in (await _json(listed))['pages']! as List)
        '${(page! as Map)['path']}': '${(page as Map)['kind']}',
    };
    expect(kinds['/'], 'code');
    expect(kinds['/blog/:slug'], 'code');
    expect(kinds['/menu'], 'override');
    expect(kinds['/landing'], 'stored');
    // Every compiled route the build found is listed -- the project's pages
    // and the account pages the framework adds -- and nothing it did not.
    expect(
      kinds.keys.toSet(),
      <String>{
        for (final DVGraphRoute route in graph.routes) route.path,
        '/landing',
      },
    );
  });

  test('a phone app: the generated route manifest is what Studio inside it '
      'lists, and a static page can be drawn as its route draws it', () async {
    final Directory app = await _project('field_notes', <String, String>{
      'lib/pages/index.dart': _page('home', '/'),
      'lib/pages/settings.dart': _page('settings', '/settings'),
      'lib/pages/notes/[id].dart': _page('note', '/notes/:id'),
    });
    await _generate(app, 'field_notes');

    expect(
      _manifest(app)..sort(),
      <String>['/', '/notes/:id', '/settings'],
      reason: 'the manifest is this project\'s pages and no one else\'s',
    );
    expect(_previews(app)..sort(), <String>['/', '/settings'],
        reason: 'a route with a parameter is a pattern, not a page to draw');

    // The Studio `dartvel admin generate` writes opens over exactly these.
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(AdminCommand(root: app.path));
    await runner.run(<String>['admin', 'generate']);
    final String studio = File(
      p.join(app.path, 'lib', 'pages', '_dartvel_admin', 'studio.page.dart'),
    ).readAsStringSync();
    expect(studio, contains('routes: dartvelRouteManifest'));
    expect(studio, contains('models: dartvelStudioModels'));
  });

  test('a model designed in Studio and written to lib/models compiles back '
      'to the model Studio stored', () async {
    const DVStudioModelSpec designed = DVStudioModelSpec(
      model: 'Booking',
      table: 'bookings',
      key: 'id',
      origin: DVStudioModelOrigin.studio,
      fields: <DVStudioFieldSpec>[
        DVStudioFieldSpec(name: 'id', type: 'String'),
        DVStudioFieldSpec(
          name: 'guest',
          type: 'String',
          minLength: 2,
          maxLength: 80,
        ),
        DVStudioFieldSpec(
          name: 'code',
          type: 'String?',
          unique: true,
          pattern: r"^[A-Z]{3}-\d+$",
        ),
        DVStudioFieldSpec(name: 'seats', type: 'int', min: 1, max: 12),
        DVStudioFieldSpec(
          name: 'status',
          type: 'BookingStatus',
          options: <String>['held', 'confirmed'],
        ),
      ],
      indexes: <DVStudioIndexSpec>[
        DVStudioIndexSpec(fields: <String>['status', 'seats']),
      ],
      access: DVModelAccess(view: DVAccess.anyone, create: DVAccess.signedIn),
    );
    for (final String project in <String>['roastery_site', 'field_notes']) {
      final Directory root = await _project(project, <String, String>{
        'lib/models/booking.dart': dvStudioModelDartSource(designed),
      });
      await _generate(root, project);

      final DVStudioModelSpec compiled = dvDevStudioModels(root.path).single;
      // The model's own save() checks the same rules before it writes.
      final String models = File(
        p.join(root.path, 'lib', 'dartvel_client', 'models.g.dart'),
      ).readAsStringSync();
      expect(models, contains("dvCheckModelRules('Booking'"));
      expect(models, contains("DVStudioFieldSpec(name: 'seats', type: 'int', min: 1, max: 12)"));
      expect(compiled.model, designed.model, reason: project);
      expect(compiled.table, designed.table);
      expect(compiled.key, designed.key);
      expect(
        jsonEncode(<Object?>[
          for (final DVStudioFieldSpec f in compiled.fields) f.toJson(),
        ]),
        jsonEncode(<Object?>[
          for (final DVStudioFieldSpec f in designed.fields) f.toJson(),
        ]),
        reason: 'the fields and their rules survive the round trip',
      );
      expect(
        jsonEncode(<Object?>[
          for (final DVStudioIndexSpec i in compiled.indexes) i.toJson(),
        ]),
        jsonEncode(<Object?>[
          for (final DVStudioIndexSpec i in designed.indexes) i.toJson(),
        ]),
      );
      expect(compiled.access?.toJson(), designed.access!.toJson());

      // And Studio, over the compiled model, checks the same rules.
      final DVStudioApi api = DVStudioApi(
        database: MemoryDVDatabaseAdapter(),
        models: <DVStudioModelSpec>[compiled],
      );
      final Response refused = await api.respond(
        Request(
          method: 'POST',
          url: Uri.parse('http://localhost/api/models/Booking/records'),
          headers: Headers(const <String, String>{
            'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
          }),
          bodyStream: Stream<List<int>>.value(utf8.encode(jsonEncode(
            <String, Object?>{
              'values': <String, Object?>{
                'id': 'b1',
                'guest': 'Ada',
                'seats': 20,
                'status': 'held',
              },
            },
          ))),
        ),
        'models/Booking/records',
      );
      expect(refused.status, 400);
      expect('${(await _json(refused))['message']}', contains('at most 12'));
    }
  });
}
