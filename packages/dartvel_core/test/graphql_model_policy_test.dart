// The GraphQL fields generated for a model ask the model's policy.
//
// A generated model registers a list query, a find query, a save mutation and
// a delete mutation on DVGraphQL, and none of them asked anything: somebody a
// policy forbade to delete a post could delete it by sending deletePost, while
// the admin screen beside it hid the button. The resolvers now ask
// DVGraphQL.authorizeModel with the record they would touch before touching
// it, the way the model admin asks through canAction.
//
// The silent failures:
//  * a model nobody wrote a policy for answering every question with yes;
//  * a policy taking the application's User asked with some other caller
//    throwing a cast error, or worse, being skipped;
//  * a policy that throws being read as an allow;
//  * a refusal that still ran the write and only hid the result.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class GqlPost {
  GqlPost(this.author);
  final String author;
}

class GqlAccount {
  GqlAccount(this.name);
  final String name;
}

class GqlUnwritten {}

void main() {
  const DVAuthAuthorization authorization = DVAuthAuthorization();

  setUpAll(() {
    authorization.registerDeclared<GqlAccount, GqlPost?>(
      'delete',
      (GqlAccount user, GqlPost? post) =>
          post != null && post.author == user.name,
    );
    authorization.registerDeclared<Object?, GqlPost?>(
      'viewAny',
      (Object? user, GqlPost? post) => throw StateError('boom'),
    );
  });

  Future<Object?> refusalOf(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } catch (error) {
      return error;
    }
  }

  test('a model no policy answers is refused, not allowed', () async {
    final Object? error = await refusalOf(
      () => DVGraphQL.authorizeModel(
        'GqlUnwritten.update',
        resource: GqlUnwritten(),
        user: GqlAccount('ada'),
      ),
    );

    expect(error, isA<DVGraphQLForbidden>());
    expect('$error', contains('GqlUnwritten.update'));
  });

  test('the policy decides on the record it is handed', () async {
    expect(
      await refusalOf(
        () => DVGraphQL.authorizeModel(
          'GqlPost.delete',
          resource: GqlPost('ada'),
          user: GqlAccount('ada'),
        ),
      ),
      isNull,
    );
    expect(
      await refusalOf(
        () => DVGraphQL.authorizeModel(
          'GqlPost.delete',
          resource: GqlPost('bob'),
          user: GqlAccount('ada'),
        ),
      ),
      isA<DVGraphQLForbidden>(),
    );
  });

  test('a caller the policy cannot take is refused rather than cast', () async {
    final Object? error = await refusalOf(
      () => DVGraphQL.authorizeModel(
        'GqlPost.delete',
        resource: GqlPost('ada'),
        user: 'ada',
      ),
    );

    expect(error, isA<DVGraphQLForbidden>());
  });

  test('a policy that throws has not said yes', () async {
    final Object? error = await refusalOf(
      () => DVGraphQL.authorizeModel('GqlPost.viewAny', user: null),
    );

    expect(error, isA<DVGraphQLForbidden>());
  });

  test(
    'a request\'s API key is the caller, and its scopes still apply',
    () async {
      final DVApiPrincipal key = DVApiPrincipal(
        kind: DVApiPrincipalKind.apiKey,
        subject: 'key-1',
        tenant: 'acme',
        scopes: <String>{'s'},
        actions: <String>{'GqlPost.view'},
      );
      // The key, not the account handed as the fallback, is who is asking --
      // and its scopes do not cover delete.
      final Object? error = await DVApiPrincipal.actingAs(
        key,
        () => refusalOf(
          () => DVGraphQL.authorizeModel(
            'GqlPost.delete',
            resource: GqlPost('ada'),
            user: GqlAccount('ada'),
          ),
        ),
      );

      expect(error, isA<DVGraphQLForbidden>());
    },
  );

  test('a resolver refused this way nulls its field as FORBIDDEN', () async {
    final List<String> wrote = <String>[];
    DVGraphQL.reset();
    DVGraphQL.registerMutation(
      DVGraphQLField(
        'deleteGqlPost',
        'Boolean!',
        resolve: (Map<String, Object?> args, Object? parent) async {
          await DVGraphQL.authorizeModel(
            'GqlPost.delete',
            resource: GqlPost('bob'),
            user: GqlAccount('ada'),
          );
          wrote.add('deleted');
          return true;
        },
      ),
    );

    final Map<String, Object?> result = await DVGraphQL.execute(
      'mutation { deleteGqlPost }',
    );

    expect(wrote, isEmpty);
    expect((result['data'] as Map?)?['deleteGqlPost'], isNull);
    final Map<Object?, Object?> error =
        (result['errors']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(error['message'], 'Not authorized (GqlPost.delete)');
    expect(error['extensions'], <String, Object?>{'code': 'FORBIDDEN'});
  });
}
