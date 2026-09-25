// Who may see a generated model page, and what it may show them.
//
// Every data model has a public page unless it opts out, so what keeps a
// sensitive field or a refused record off the web is this: the policy
// questions a page asks, and the page data the server and the static build
// make from a row. Both are asserted on what reaches a reader -- the page
// data's JSON, which is what the head, the structured data, the crawler text
// and the shared page cache are all made from -- rather than on which fields
// a spec names.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/framework.dart' show DVModelPageAccess;
import 'package:test/test.dart';

/// Everything a page could leak, as one string to search.
String everything(DVPageData? data) => jsonEncode(data?.toJson());

void main() {
  setUp(DVAuthAuthorization.reset);
  tearDown(DVAuthAuthorization.reset);

  const DVModelPageAccess access = DVModelPageAccess();

  group('whether a viewer may have a record\'s page', () {
    test('a model with no view policy is public', () async {
      expect(await access.mayView('Article', null, <String, Object?>{}),
          isTrue);
    });

    test('a record that is its own privacy subject is refused with no policy',
        () async {
      // A row that is a person is nobody's to publish by default.
      expect(
          await access.mayView('Customer', null, <String, Object?>{},
              personal: true),
          isFalse);
    });

    test('a view policy declared where this process cannot load it refuses',
        () async {
      // The server cannot load a policy written against the generated
      // client. Reading that as "no policy" would publish every record the
      // policy exists to refuse.
      expect(
          await access.mayView('Article', null, <String, Object?>{},
              declaredViewPolicy: true),
          isFalse);
    });

    test('a registered view policy decides, asked with the viewer and record',
        () async {
      final List<Object?> asked = <Object?>[];
      const DVAuthAuthorization().registerAction('Article.view',
          (Object? viewer, Object? record) {
        asked.add(viewer);
        return record is Map && record['published'] == true;
      });
      expect(
          await access.mayView(
              'Article', 'ada', <String, Object?>{'published': true}),
          isTrue);
      expect(
          await access.mayView(
              'Article', 'ada', <String, Object?>{'published': false}),
          isFalse);
      expect(asked, <Object?>['ada', 'ada']);
    });

    test('a registered view policy can admit a personal record', () async {
      const DVAuthAuthorization().registerAction(
          'Customer.view', (Object? viewer, Object? record) => viewer == 'ada');
      expect(
          await access.mayView('Customer', 'ada', <String, Object?>{},
              personal: true),
          isTrue);
      expect(
          await access.mayView('Customer', null, <String, Object?>{},
              personal: true),
          isFalse);
    });

    test('a policy that throws refuses', () async {
      const DVAuthAuthorization().registerAction(
          'Article.view', (Object? viewer, Object? record) => throw StateError('db down'));
      expect(await access.mayView('Article', null, <String, Object?>{}),
          isFalse);
    });

    test('a policy that cannot be asked about this record refuses', () async {
      // Typed on a resource the caller does not have: the server holds a row,
      // not the generated model.
      const DVAuthAuthorization()
          .registerDeclared<Object?, Article>('view', (_, __) => true);
      expect(await access.mayView('Article', null, <String, Object?>{}),
          isFalse);
    });
  });

  group('whether a viewer may see protected fields', () {
    test('nobody may without a viewSensitive policy, even with a view policy',
        () async {
      const DVAuthAuthorization()
          .registerAction('Article.view', (Object? viewer, Object? record) => true);
      expect(
          await access.mayViewProtected('Article', 'ada', <String, Object?>{}),
          isFalse);
    });

    test('the viewSensitive policy decides per viewer', () async {
      const DVAuthAuthorization().registerAction('Article.viewSensitive',
          (Object? viewer, Object? record) => viewer == 'editor');
      expect(
          await access.mayViewProtected(
              'Article', 'editor', <String, Object?>{}),
          isTrue);
      expect(
          await access.mayViewProtected(
              'Article', 'reader', <String, Object?>{}),
          isFalse);
      expect(
          await access.mayViewProtected('Article', null, <String, Object?>{}),
          isFalse);
    });

    test('a viewSensitive policy that throws refuses', () async {
      const DVAuthAuthorization().registerAction('Article.viewSensitive',
          (Object? viewer, Object? record) => throw StateError('db down'));
      expect(
          await access.mayViewProtected(
              'Article', 'editor', <String, Object?>{}),
          isFalse);
    });
  });

  group('page data never carries a protected field', () {
    // Every place a value could be taken from names a protected field, as a
    // generator that got it wrong would. The spec's protected set wins.
    const DVModelPageSpec careless = DVModelPageSpec(
      model: 'Article',
      route: '/articles/:slug',
      param: 'slug',
      table: 'articles',
      keyField: 'slug',
      titleField: 'editorNotes',
      contentFields: <String>['body', 'editorNotes', 'authorId'],
      imageField: 'privatePhoto',
      protectedFields: <String>{'editorNotes', 'authorId', 'privatePhoto'},
    );
    const Map<String, Object?> row = <String, Object?>{
      'slug': 'hello-world',
      'body': 'Short body',
      'editorNotes': 'SECRET-NOTES that are much longer than the body',
      'authorId': 'SECRET-AUTHOR-ID-and-it-is-long-too',
      'privatePhoto': '/SECRET-PHOTO.png',
    };

    test('not in the title, description, text, image or structured data', () {
      final DVPageData data = dvModelPageData(careless, row);
      expect(everything(data), isNot(contains('SECRET')));
      expect(data.description, 'Short body');
      expect(data.image, isNull);
      expect(data.visibility, DVPageVisibility.public);
    });

    test('a protected key is not the title either', () {
      const DVModelPageSpec keyed = DVModelPageSpec(
        model: 'Article',
        route: '/articles/:code',
        param: 'code',
        table: 'articles',
        keyField: 'code',
        protectedFields: <String>{'code'},
      );
      final DVPageData data =
          dvModelPageData(keyed, <String, Object?>{'code': 'SECRET-CODE'});
      expect(everything(data), isNot(contains('SECRET')));
      expect(data.title, 'Article');
    });

    test('a personal record has no page data at all', () {
      const DVModelPageSpec personal = DVModelPageSpec(
        model: 'Customer',
        route: '/customers/:id',
        param: 'id',
        table: 'customers',
        keyField: 'id',
        titleField: 'name',
        personal: true,
      );
      final DVPageData data = dvModelPageData(
          personal, <String, Object?>{'id': 'c1', 'name': 'SECRET Ada'});
      expect(everything(data), isNot(contains('SECRET')));
      expect(data.visibility, DVPageVisibility.hidden);
    });

    test('an unpublished record is the same as a missing one', () {
      const DVModelPageSpec spec = DVModelPageSpec(
        model: 'Article',
        route: '/articles/:slug',
        param: 'slug',
        table: 'articles',
        keyField: 'slug',
        titleField: 'title',
        publishedField: 'published',
      );
      final DVPageData data = dvModelPageData(spec, <String, Object?>{
        'slug': 'draft',
        'title': 'SECRET draft title',
        'published': 0,
      });
      expect(everything(data), isNot(contains('SECRET')));
      expect(data.visibility, DVPageVisibility.hidden);
    });
  });

  group('the server\'s page resolver', () {
    const DVModelPageSpec spec = DVModelPageSpec(
      model: 'Article',
      route: '/articles/:slug',
      param: 'slug',
      table: 'articles',
      keyField: 'slug',
      titleField: 'title',
      contentFields: <String>['body'],
      protectedFields: <String>{'editorNotes'},
    );
    Future<List<Map<String, Object?>>> rows(String sql, List<Object?> params) async =>
        params.first == 'missing'
            ? <Map<String, Object?>>[]
            : <Map<String, Object?>>[
                <String, Object?>{
                  'slug': params.first,
                  'title': 'Title of ${params.first}',
                  'body': 'Body',
                  'editorNotes': 'SECRET',
                  'draft': params.first == 'draft',
                },
              ];
    DVPageRequest request(String slug) => DVPageRequest(
        path: '/articles/$slug',
        pattern: '/articles/:slug',
        params: <String, String>{'slug': slug},
        headers: const <String, String>{'authorization': 'Bearer editor'});

    test('a refused record answers exactly as a missing one', () async {
      const DVAuthAuthorization().registerAction('Article.view',
          (Object? viewer, Object? record) => record is Map && record['draft'] != true);
      final DVPageDataResolver resolve = dvModelPageResolver(
          <DVModelPageSpec>[spec], rows);
      final DVPageData? refused = await resolve(request('draft'));
      final DVPageData? missing = await resolve(request('missing'));
      expect(refused!.visibility, DVPageVisibility.hidden);
      expect(everything(refused), everything(missing));
      expect(everything(refused), isNot(contains('draft')));
      final DVPageData? shown = await resolve(request('hello'));
      expect(shown!.title, 'Title of hello');
      expect(everything(shown), isNot(contains('SECRET')));
    });

    test('asks as nobody, because what it resolves is shared', () async {
      // Page data is cached per path and served to everyone, so a record
      // one signed-in reader may see must not be resolved as them.
      final List<Object?> viewers = <Object?>[];
      const DVAuthAuthorization().registerAction('Article.view',
          (Object? viewer, Object? record) {
        viewers.add(viewer);
        return viewer != null;
      });
      final DVPageDataResolver resolve = dvModelPageResolver(
          <DVModelPageSpec>[spec], rows);
      final DVPageData? page = await resolve(request('hello'));
      expect(viewers, <Object?>[null]);
      expect(page!.visibility, DVPageVisibility.hidden);
    });

    test('a personal model is never resolved with data', () async {
      const DVAuthAuthorization().registerAction(
          'Customer.view', (Object? viewer, Object? record) => true);
      const DVModelPageSpec personal = DVModelPageSpec(
        model: 'Customer',
        route: '/customers/:id',
        param: 'id',
        table: 'customers',
        keyField: 'id',
        titleField: 'title',
        personal: true,
      );
      final DVPageData? page = await dvModelPageResolver(
          <DVModelPageSpec>[personal], rows)(const DVPageRequest(
              path: '/customers/c1',
              pattern: '/customers/:id',
              params: <String, String>{'id': 'c1'}));
      expect(page!.visibility, DVPageVisibility.hidden);
      expect(everything(page), isNot(contains('c1')));
    });
  });
}

/// Stands in for a generated model the server cannot import.
class Article {
  const Article();
}
