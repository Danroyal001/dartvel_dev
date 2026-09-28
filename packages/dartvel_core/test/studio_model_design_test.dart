// Data models designed in Studio, and every page the site answers.
//
// Studio could only show the records of a model somebody had written in
// code, so an owner who wanted a new kind of record had to write Dart and
// rebuild. A model designed in Studio is stored beside its records and
// served at once: its fields, the rules a value has to meet, its relations,
// its indexes and who may do what -- through Studio, and through the data API
// an application reads it with. On a development server it is also written
// out to lib/models as the @DVModel it compiles back from.
//
// Studio's Pages listed only what Studio had stored, so a site of fifty
// compiled pages opened on "0 pages". The site endpoint is both: every
// compiled route from the build's graph and every stored page, each marked
// code, stored or override.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVAdminMount _guarded = DVAdminMount(
  path: '/__studio',
  enabled: true,
  requiresAuth: true,
);

const String _csrf = 'abcdefghijklmnopqrstuvwxyz012345';

Request _request(
  String method,
  String path, {
  Object? json,
  bool csrf = true,
}) => Request(
  method: method,
  url: Uri.parse('http://localhost:8080$path'),
  headers: Headers(<String, String>{
    if (json != null) 'content-type': 'application/json',
    if (csrf) 'x-dartvel-csrf-token': _csrf,
  }),
  bodyStream: json == null
      ? const Stream<List<int>>.empty()
      : Stream<List<int>>.value(utf8.encode(jsonEncode(json))),
);

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(utf8.decode(await response.body!.bytes())) as Map)
        .cast<String, Object?>();

/// An article, as the designer sends one.
Map<String, Object?> _article({
  List<Map<String, Object?>>? extra,
  Map<String, Object?>? access,
}) => <String, Object?>{
  'key': 'id',
  'fields': <Object?>[
    <String, Object?>{'name': 'id', 'type': 'String'},
    <String, Object?>{
      'name': 'title',
      'type': 'String',
      'minLength': 3,
      'maxLength': 40,
    },
    <String, Object?>{
      'name': 'slug',
      'type': 'String?',
      'unique': true,
      'pattern': r'[a-z0-9-]+',
    },
    <String, Object?>{'name': 'views', 'type': 'int?', 'min': 0},
    <String, Object?>{
      'name': 'status',
      'type': 'ArticleStatus',
      'options': <String>['draft', 'published'],
    },
    ...?extra,
  ],
  'indexes': <Object?>[
    <String, Object?>{
      'fields': <String>['status', 'views'],
    },
  ],
  'access': access,
};

void main() {
  late Directory root;
  late Directory source;
  late MemoryDVDatabaseAdapter database;
  late DVAdminServer server;
  bool granted = true;

  DVAdminServer serverWith({String? sourceRoot}) => DVAdminServer(
    mount: _guarded,
    root: root.path,
    authenticated: (Request _) async => granted,
    models: const <DVStudioModelSpec>[
      DVStudioModelSpec(
        model: 'Author',
        table: 'authors',
        key: 'slug',
        fields: <DVStudioFieldSpec>[
          DVStudioFieldSpec(name: 'slug', type: 'String'),
          DVStudioFieldSpec(name: 'name', type: 'String'),
        ],
      ),
    ],
    database: database,
    sourceRoot: sourceRoot,
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_studio_design_');
    source = Directory.systemTemp.createTempSync('dartvel_studio_source_');
    addTearDown(() {
      root.deleteSync(recursive: true);
      source.deleteSync(recursive: true);
    });
    File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
    database = MemoryDVDatabaseAdapter();
    granted = true;
    server = serverWith();
  });

  Future<Response> send(
    String method,
    String path, {
    Object? json,
    DVAdminServer? through,
  }) async {
    final Response? response = await (through ?? server).respond(
      _request(method, '/__studio/api/$path', json: json),
    );
    expect(response, isNotNull, reason: '$method $path went unanswered');
    return response!;
  }

  group('a model designed in Studio', () {
    test('is stored, listed as Studio\'s, and served at once', () async {
      final Response created = await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      expect(created.status, 201, reason: '${await _json(created)}');

      final Map<String, Object?> listed = await _json(
        await send('GET', 'models'),
      );
      final List<Map<String, Object?>> models =
          (listed['models']! as List<Object?>).cast<Map<String, Object?>>();
      expect(
        <String>[for (final Map<String, Object?> m in models) '${m['model']}'],
        <String>['Author', 'Article'],
      );
      expect(models.first['origin'], 'code');
      expect(models.last['origin'], 'studio');
      expect(listed['sourceWritable'], isFalse);

      final Response record = await send(
        'POST',
        'models/Article/records',
        json: <String, Object?>{
          'values': <String, Object?>{
            'title': 'Hello there',
            'slug': 'hello',
            'status': 'draft',
          },
        },
      );
      final Map<String, Object?> saved = await _json(record);
      expect(record.status, 201, reason: '$saved');
      // Nobody typed an id, and a record needs one.
      expect('${saved['key']}', hasLength(20));
      expect((saved['values']! as Map<String, Object?>)['title'], 'Hello there');
    });

    test('keeps its records in the table its @DVModel would', () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      await send(
        'POST',
        'models/Article/records',
        json: <String, Object?>{
          'values': <String, Object?>{'id': 'a1', 'title': 'Hello', 'status': 'draft'},
        },
      );
      final List<Map<String, Object?>> rows = await database.query(
        'SELECT * FROM articles',
      );
      expect(rows.single['id'], 'a1');
    });

    test('refuses a value its rules do not allow', () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      for (final (Map<String, Object?> values, String why) in <(Map<String, Object?>, String)>[
        (<String, Object?>{'title': 'Hi', 'status': 'draft'}, 'at least 3'),
        (<String, Object?>{'title': 'x' * 41, 'status': 'draft'}, 'at most 40'),
        (
          <String, Object?>{'title': 'Hello', 'slug': 'Not A Slug', 'status': 'draft'},
          'pattern',
        ),
        (<String, Object?>{'title': 'Hello', 'views': -1, 'status': 'draft'}, 'at least 0'),
        (<String, Object?>{'title': 'Hello', 'status': 'gone'}, 'one of'),
        (<String, Object?>{'status': 'draft'}, 'title cannot be empty'),
      ]) {
        final Response refused = await send(
          'POST',
          'models/Article/records',
          json: <String, Object?>{'values': values},
        );
        expect(refused.status, 400, reason: why);
        expect('${(await _json(refused))['message']}', contains(why));
      }
    });

    test('refuses a second record with a value no two may share', () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      final Map<String, Object?> values = <String, Object?>{
        'title': 'Hello',
        'slug': 'hello',
        'status': 'draft',
      };
      expect(
        (await send(
          'POST',
          'models/Article/records',
          json: <String, Object?>{'values': values},
        )).status,
        201,
      );
      final Response twice = await send(
        'POST',
        'models/Article/records',
        json: <String, Object?>{'values': values},
      );
      expect(twice.status, 409);
      expect('${(await _json(twice))['message']}', contains('slug hello'));
    });

    test('refers to another model by its key, and only to one that exists',
        () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{
          'definition': _article(
            extra: <Map<String, Object?>>[
              <String, Object?>{
                'name': 'authorSlug',
                'type': 'String?',
                'relation': 'Author',
              },
            ],
          ),
        },
      );
      final Response dangling = await send(
        'POST',
        'models/Article/records',
        json: <String, Object?>{
          'values': <String, Object?>{
            'title': 'Hello',
            'status': 'draft',
            'authorSlug': 'nobody',
          },
        },
      );
      expect(dangling.status, 400);
      expect('${(await _json(dangling))['message']}', contains('Author'));
    });

    test('grows a field its table did not have', () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      await send(
        'POST',
        'models/Article/records',
        json: <String, Object?>{
          'values': <String, Object?>{'id': 'a1', 'title': 'Hello', 'status': 'draft'},
        },
      );
      final Response grown = await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{
          'definition': _article(
            extra: <Map<String, Object?>>[
              <String, Object?>{'name': 'summary', 'type': 'String?'},
            ],
          ),
        },
      );
      expect(grown.status, 200, reason: '${await _json(grown)}');
      final Response edited = await send(
        'PUT',
        'models/Article/records/a1',
        json: <String, Object?>{
          'version': 1,
          'values': <String, Object?>{'summary': 'Short'},
        },
      );
      final Map<String, Object?> editedBody = await _json(edited);
      expect(edited.status, 200, reason: '$editedBody');
      expect(
        (editedBody['values']! as Map<String, Object?>)['summary'],
        'Short',
      );
    });

    test('is refused with every problem its definition has', () async {
      final Response refused = await send(
        'PUT',
        'models/article',
        json: <String, Object?>{
          'definition': <String, Object?>{
            'key': 'id',
            'fields': <Object?>[
              <String, Object?>{'name': 'id', 'type': 'String'},
              <String, Object?>{'name': 'Title', 'type': 'Money'},
            ],
          },
        },
      );
      expect(refused.status, 400);
      final List<Object?> problems =
          (await _json(refused))['problems']! as List<Object?>;
      expect(problems.join('\n'), contains('PascalCase'));
      expect(problems.join('\n'), contains('camelCase'));
      expect(problems.join('\n'), contains('Money is not a type'));
    });

    test('cannot take the name of a model written in code', () async {
      final Response refused = await send(
        'PUT',
        'models/Author',
        json: <String, Object?>{
          'definition': <String, Object?>{
            'key': 'slug',
            'fields': <Object?>[
              <String, Object?>{'name': 'slug', 'type': 'String'},
            ],
          },
        },
      );
      expect(refused.status, 409);
      expect((await _json(refused))['error'], 'in_code');
    });

    test('keeps its records when it is deleted, and finds them again',
        () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      await send(
        'POST',
        'models/Article/records',
        json: <String, Object?>{
          'values': <String, Object?>{'id': 'a1', 'title': 'Hello', 'status': 'draft'},
        },
      );
      expect((await send('DELETE', 'models/Article')).status, 200);
      expect((await send('GET', 'models/Article/records')).status, 404);

      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      final List<Object?> records =
          (await _json(await send('GET', 'models/Article/records')))['records']!
              as List<Object?>;
      expect(records, hasLength(1));
    });

    test('is nothing to a caller who may not open Studio', () async {
      granted = false;
      for (final Request request in <Request>[
        _request('GET', '/__studio/api/site'),
        _request(
          'PUT',
          '/__studio/api/models/Article',
          json: <String, Object?>{'definition': _article()},
        ),
        _request('DELETE', '/__studio/api/models/Article'),
        _request('POST', '/__studio/api/models/Article/source'),
      ]) {
        expect(await server.respond(request), isNull, reason: request.url.path);
      }
      granted = true;
      expect(
        (await _json(await send('GET', 'models')))['models'],
        hasLength(1),
        reason: 'nothing was stored',
      );
    });
  });

  group('written to source', () {
    test('only where there is a source tree', () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      final Response refused = await send('POST', 'models/Article/source');
      expect(refused.status, 404);
      expect((await _json(refused))['error'], 'no_source');
    });

    test('as the @DVModel that compiles back to the same model', () async {
      final DVAdminServer dev = serverWith(sourceRoot: source.path);
      expect(
        (await _json(await send('GET', 'models', through: dev)))['sourceWritable'],
        isTrue,
      );
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{
          'definition': _article(
            access: <String, Object?>{'view': 'anyone'},
          ),
        },
        through: dev,
      );
      final Response written = await send(
        'POST',
        'models/Article/source',
        through: dev,
      );
      final Map<String, Object?> writtenBody = await _json(written);
      expect(written.status, 200, reason: '$writtenBody');
      expect(writtenBody['source'], 'lib/models/article.dart');

      final String dart =
          File('${source.path}/lib/models/article.dart').readAsStringSync();
      expect(dart, startsWith(dvStudioModelSourceMarker));
      expect(dart, contains('enum ArticleStatus { draft, published }'));
      expect(dart, contains('class const _Article({'));
      // The key first, which is the field the generator finds records by.
      expect(
        dart.indexOf('required final String id,'),
        lessThan(dart.indexOf('required final String title,')),
      );
      expect(dart, contains('@DVModel.validate(minLength: 3, maxLength: 40)'));
      expect(dart, contains('@DVModel.uniqueField()'));
      expect(dart, contains("pattern: '[a-z0-9-]+'"));
      expect(dart, contains('final int? views,'));
      expect(dart, contains('access: DVModelAccess(view: DVAccess.anyone'));
      expect(
        dart,
        contains("indexes: <DVIndex>[DVIndex(<String>['status', 'views'])]"),
      );
    });

    test('never over a model file somebody wrote by hand', () async {
      final DVAdminServer dev = serverWith(sourceRoot: source.path);
      final File mine = File('${source.path}/lib/models/article.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('// mine\n');
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
        through: dev,
      );
      final Response refused = await send(
        'POST',
        'models/Article/source',
        through: dev,
      );
      expect(refused.status, 409);
      expect(mine.readAsStringSync(), '// mine\n');
    });
  });

  group('the site', () {
    void graph(List<Map<String, Object?>> routes) =>
        File('${root.path}/graph.json').writeAsStringSync(
          jsonEncode(<String, Object?>{'routes': routes}),
        );

    test('is every compiled route and every stored page, each marked',
        () async {
      graph(<Map<String, Object?>>[
        <String, Object?>{
          'path': '/',
          'page': 'indexPage',
          'source': 'lib/pages/index.dart:5',
          'kind': 'page',
        },
        <String, Object?>{
          'path': '/features',
          'page': 'featuresPage',
          'source': 'lib/pages/features.dart:5',
          'kind': 'page',
        },
        <String, Object?>{
          'path': '/articles/:slug',
          'page': 'articlePage',
          'source': 'lib/pages/articles/[slug].dart:5',
          'kind': 'page',
        },
      ]);
      Directory('${root.path}/structure').createSync();
      File('${root.path}/structure/features.json').writeAsStringSync(
        jsonEncode(<Object?>[
          <String, Object?>{'role': null, 'level': 1, 'label': 'Features'},
        ]),
      );
      for (final (String route, String title) in <(String, String)>[
        ('/features', 'Features, edited'),
        ('/landing', 'Landing'),
      ]) {
        await send(
          'PUT',
          'pages',
          json: <String, Object?>{
            'document': <String, Object?>{
              'route': route,
              'title': title,
              'root': <String, Object?>{'type': 'box'},
            },
          },
        );
      }

      final List<Map<String, Object?>> pages =
          ((await _json(await send('GET', 'site')))['pages']! as List<Object?>)
              .cast<Map<String, Object?>>();
      expect(
        <String>[
          for (final Map<String, Object?> p in pages) '${p['path']} ${p['kind']}',
        ],
        <String>[
          '/ code',
          '/articles/:slug code',
          '/features override',
          '/landing stored',
        ],
      );
      final Map<String, Object?> article = pages[1];
      expect(article['params'], <String>['slug']);
      expect(article['source'], 'lib/pages/articles/[slug].dart:5');
      expect(pages[2]['structure'], isTrue);
      expect(pages[2]['title'], 'Features, edited');
      expect(pages.first['structure'], isNull);

      final Response structure = await send(
        'GET',
        'site/structure?route=%2Ffeatures',
      );
      expect(structure.status, 200);
      expect(
        jsonEncode((await _json(structure))['structure']),
        contains('Features'),
      );
      expect(
        (await send('GET', 'site/structure?route=%2F..%2Fgraph')).status,
        404,
      );
    });

    test('with no graph is the stored pages alone', () async {
      await send(
        'PUT',
        'pages',
        json: <String, Object?>{
          'document': <String, Object?>{
            'route': '/landing',
            'root': <String, Object?>{'type': 'box'},
          },
        },
      );
      final List<Object?> pages =
          (await _json(await send('GET', 'site')))['pages']! as List<Object?>;
      expect(
        pages.single,
        containsPair('kind', 'stored'),
      );
    });
  });

  test('a model saved in code meets the same rules', () {
    const List<DVStudioFieldSpec> rules = <DVStudioFieldSpec>[
      DVStudioFieldSpec(name: 'title', type: 'String', minLength: 3),
      DVStudioFieldSpec(name: 'seats', type: 'int', max: 12),
    ];
    expect(
      () => dvCheckModelRules('Article', rules, <String, Object?>{
        'title': 'Hi',
        'seats': 2,
      }),
      throwsA(
        isA<DVModelRuleError>()
            .having((DVModelRuleError e) => e.field, 'field', 'title')
            .having((DVModelRuleError e) => e.message, 'message',
                'title has to be at least 3 characters.'),
      ),
    );
    dvCheckModelRules('Article', rules, <String, Object?>{
      'title': 'Hello',
      'seats': 12,
    });
  });

  group('the data API', () {
    late DVModelDataApi data;
    setUp(() {
      data = DVModelDataApi(
        database: () => database,
        team: (Request _) async => granted,
      );
    });

    Future<Response?> call(String method, String path, {Object? json}) =>
        data.respond(_request(method, '/_dartvel/data/$path', json: json));

    test('serves a model to whom its access allows, and no one else',
        () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{
          'definition': _article(
            access: <String, Object?>{
              'view': 'anyone',
              'create': 'team',
              'update': 'nobody',
              'delete': 'team',
            },
          ),
        },
      );
      granted = false;
      final Response? listed = await call('GET', 'Article');
      expect(listed?.status, 200);
      expect((await _json(listed!))['records'], isEmpty);
      final Response? schema = await call('GET', 'Article/schema');
      expect((await _json(schema!))['fields'], hasLength(5));

      final Response? stranger = await call(
        'POST',
        'Article',
        json: <String, Object?>{
          'values': <String, Object?>{'title': 'Hello', 'status': 'draft'},
        },
      );
      expect(stranger?.status, 401);

      granted = true;
      final Response? created = await call(
        'POST',
        'Article',
        json: <String, Object?>{
          'values': <String, Object?>{
            'id': 'a1',
            'title': 'Hello',
            'status': 'draft',
          },
        },
      );
      expect(created?.status, 201, reason: '${await _json(created!)}');
      // Nobody changes one through the API, the team included.
      final Response? change = await call(
        'PUT',
        'Article/a1',
        json: <String, Object?>{
          'version': 1,
          'values': <String, Object?>{'title': 'Changed'},
        },
      );
      expect(change?.status, 401);
      // The same rules as Studio's.
      final Response? short = await call(
        'POST',
        'Article',
        json: <String, Object?>{
          'values': <String, Object?>{'title': 'Hi', 'status': 'draft'},
        },
      );
      expect(short?.status, 400);
    });

    test('does not name a model somebody may not read', () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{'definition': _article()},
      );
      granted = false;
      expect(await call('GET', 'Article'), isNull);
      expect(await call('GET', 'Article/a1'), isNull);
      // Nor one written in code: that model has its own class to be read by.
      granted = true;
      expect(await call('GET', 'Author'), isNull);
    });

    test('refuses a write without the CSRF header', () async {
      await send(
        'PUT',
        'models/Article',
        json: <String, Object?>{
          'definition': _article(
            access: <String, Object?>{'create': 'anyone'},
          ),
        },
      );
      final Response? forged = await data.respond(
        _request(
          'POST',
          '/_dartvel/data/Article',
          json: <String, Object?>{
            'values': <String, Object?>{'title': 'Hello', 'status': 'draft'},
          },
          csrf: false,
        ),
      );
      expect(forged?.status, 403);
    });
  });
}
