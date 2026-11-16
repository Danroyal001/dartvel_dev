// Studio's Platforms screen writes dartvel.platforms, the same object code
// writes: into pubspec.yaml on a development server, and through the GitHub
// screen on a deployed one, so a change made in Studio is a diff in code and
// a change made in code is what Studio shows.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

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

const Map<String, Object?> _document = <String, Object?>{
  'head': <Object?>[
    <String, Object?>{'html': '<meta name="theme-color" content="#000">'},
  ],
  'bodyEnd': <Object?>[
    <String, Object?>{'html': '<script>window.chat = 1;</script>'},
  ],
};

void main() {
  group('the pubspec edit', () {
    const String pubspec = 'name: roastery\n'
        '# The site.\n'
        'dartvel:\n'
        '  seo:\n'
        '    siteName: Roastery # shown in tabs\n'
        '  web:\n'
        '    firstFrame:\n'
        '      widths: [390]\n'
        '    document:\n'
        '      head:\n'
        '        - html: <meta name="old" content="1">\n';

    test('writes platforms.web.document and keeps every other line', () {
      final String out = dvStudioPubspecWithPlatforms(pubspec, _document);
      expect(out, contains('# The site.'));
      expect(out, contains('siteName: Roastery # shown in tabs'));
      final YamlMap dartvel = (loadYaml(out) as YamlMap)['dartvel'] as YamlMap;
      expect(jsonDecode(jsonEncode(dartvel['platforms'])), <String, Object?>{
        'web': <String, Object?>{'document': _document},
      });
      // The old home of the same setting is moved, not left to disagree.
      expect((dartvel['web'] as YamlMap).containsKey('document'), isFalse);
      expect((dartvel['web'] as YamlMap)['firstFrame'], isNotNull);
    });

    test('an empty document removes the setting', () {
      final String once = dvStudioPubspecWithPlatforms(pubspec, _document);
      final String out = dvStudioPubspecWithPlatforms(once, const <String, Object?>{});
      final YamlMap dartvel = (loadYaml(out) as YamlMap)['dartvel'] as YamlMap;
      expect(dartvel.containsKey('platforms'), isFalse);
      expect(dartvel['seo'], isNotNull);
    });

    test('a pubspec with no dartvel section gets one', () {
      final String out = dvStudioPubspecWithPlatforms('name: shop\n', _document);
      expect(((loadYaml(out) as YamlMap)['dartvel'] as YamlMap)['platforms'], isNotNull);
    });

    test('a project configured in Dart is told where to change it', () {
      expect(
        () => dvStudioPubspecWithPlatforms('name: shop\ndartvel: lib/dartvel_config.dart\n', _document),
        throwsA(isA<DVStudioPlatformsRefusal>()
            .having((DVStudioPlatformsRefusal r) => r.message, 'message', contains('lib/dartvel_config.dart'))),
      );
    });
  });

  group('the API', () {
    late MemoryDVDatabaseAdapter database;
    late Directory admin;

    setUp(() {
      database = MemoryDVDatabaseAdapter();
      admin = Directory.systemTemp.createTempSync('dv_studio_platforms_');
      File(p.join(admin.path, 'graph.json')).writeAsStringSync(jsonEncode(<String, Object?>{
        'routes': <Object?>[],
        'platforms': <String, Object?>{
          'source': 'pubspec',
          'web': <String, Object?>{
            'document': <String, Object?>{
              'head': <Object?>[
                <String, Object?>{'file': 'web/head.html'},
              ],
            },
          },
          'files': <String, Object?>{'web/head.html': '<meta name="built" content="1">'},
        },
      }));
    });
    tearDown(() {
      admin.deleteSync(recursive: true);
      DVAuthAuthorization.reset();
    });

    Future<(int, Map<String, Object?>)> call(DVStudioApi api, String method, String path, {Object? body}) async {
      final Response response = await api.respond(_request(method, path, body: body), path);
      final String text = utf8.decode(await response.body!.bytes());
      return (response.status, (jsonDecode(text) as Map).cast<String, Object?>());
    }

    test('shows what the build was made with, and the edges it produced', () async {
      final DVStudioApi api = DVStudioApi(database: database, root: admin.path);
      final (int status, Map<String, Object?> body) = await call(api, 'GET', 'platforms');
      expect(status, 200);
      expect(body['pending'], isFalse);
      expect(body['canEdit'], isTrue);
      expect(((body['web'] as Map)['document'] as Map)['head'], <Object?>[
        <String, Object?>{'file': 'web/head.html'},
      ]);
      expect((body['effective'] as Map)['head'], '<meta name="built" content="1">');
    });

    test('HTML that would break the page is refused with the reasons, and nothing is saved', () async {
      final DVStudioApi api = DVStudioApi(database: database, root: admin.path);
      final (int status, Map<String, Object?> body) = await call(api, 'PUT', 'platforms/web/document',
          body: <String, Object?>{
            'document': <String, Object?>{
              'bodyStart': <Object?>[
                <String, Object?>{'html': '<div>Sale'},
              ],
            },
          });
      expect(status, 422);
      expect('${body['problems']}', contains('<div>'));
      final (_, Map<String, Object?> after) = await call(api, 'GET', 'platforms');
      expect(after['pending'], isFalse);
    });

    test('a saved change waits for GitHub on a deployed server, and Studio shows it', () async {
      final DVStudioApi api = DVStudioApi(database: database, root: admin.path);
      final (int status, Map<String, Object?> saved) =
          await call(api, 'PUT', 'platforms/web/document', body: <String, Object?>{'document': _document});
      expect(status, 200);
      expect(saved['written'], isNull);
      final (_, Map<String, Object?> body) = await call(api, 'GET', 'platforms');
      expect(body['pending'], isTrue);
      expect((body['web'] as Map)['document'], _document);
    });

    test('on a development server the change is written to pubspec.yaml at once', () async {
      final Directory project = Directory.systemTemp.createTempSync('dv_studio_project_');
      addTearDown(() => project.deleteSync(recursive: true));
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('name: shop\ndartvel:\n  seo:\n    siteName: Shop\n');
      final DVStudioApi api = DVStudioApi(database: database, root: admin.path, sourceRoot: project.path);
      final (int status, Map<String, Object?> saved) =
          await call(api, 'PUT', 'platforms/web/document', body: <String, Object?>{'document': _document});
      expect(status, 200);
      expect(saved['written'], 'pubspec.yaml');
      final YamlMap dartvel =
          (loadYaml(File(p.join(project.path, 'pubspec.yaml')).readAsStringSync()) as YamlMap)['dartvel'] as YamlMap;
      expect(jsonDecode(jsonEncode((dartvel['platforms'] as YamlMap)['web'])), <String, Object?>{'document': _document});
    });

    test('on a development server a file that is not there is refused', () async {
      final Directory project = Directory.systemTemp.createTempSync('dv_studio_project_');
      addTearDown(() => project.deleteSync(recursive: true));
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('name: shop\n');
      final DVStudioApi api = DVStudioApi(database: database, root: admin.path, sourceRoot: project.path);
      final (int status, Map<String, Object?> body) = await call(api, 'PUT', 'platforms/web/document',
          body: <String, Object?>{
            'document': <String, Object?>{
              'head': <Object?>[
                <String, Object?>{'file': 'web/nope.html'},
              ],
            },
          });
      expect(status, 422);
      expect('${body['problems']}', contains('web/nope.html'));
    });

    test('an application that names who may edit raw HTML is asked, and a refusal saves nothing', () async {
      const DVAuthAuthorization().registerAction(dvStudioEditPlatformsAction, (Object? caller, Object? _) => false);
      final DVStudioApi api = DVStudioApi(database: database, root: admin.path);
      final (int status, _) =
          await call(api, 'PUT', 'platforms/web/document', body: <String, Object?>{'document': _document});
      expect(status, 403);
      final (_, Map<String, Object?> body) = await call(api, 'GET', 'platforms');
      expect(body['canEdit'], isFalse);
      expect(body['pending'], isFalse);
    });
  });

  group('the screen as a document', () {
    const DVStudioProjectData data = DVStudioProjectData(platforms: <String, Object?>{
      'web': <String, Object?>{
        'document': <String, Object?>{
          'head': <Object?>[
            <String, Object?>{'file': 'web/head.html'},
          ],
          'bodyEnd': <Object?>[
            <String, Object?>{'html': '<script>window.chat = 1;</script>'},
          ],
        },
      },
    });

    test('Platforms lists each platform with its own address', () {
      final DVStudioDocument document = dvStudioDocumentFor(
        dvStudioTargetFor('/__studio/platforms', mount: '/__studio')!,
        mount: '/__studio',
        data: data,
      );
      expect(document.heading, 'Platforms');
      expect(document.html, contains('href="/__studio/platforms/web"'));
    });

    test('Web lists every snippet by slot, as text a reader can find', () {
      final DVStudioDocument document = dvStudioDocumentFor(
        dvStudioTargetFor('/__studio/platforms/web', mount: '/__studio')!,
        mount: '/__studio',
        data: data,
      );
      expect(document.heading, 'Web');
      expect(document.html, contains('Inside the head'));
      expect(document.html, contains('web/head.html'));
      // Shown as text, never as markup that would run inside Studio.
      expect(document.html, contains('&lt;script&gt;window.chat = 1;&lt;/script&gt;'));
      expect(document.html, isNot(contains('<script>window.chat')));
    });
  });
}
