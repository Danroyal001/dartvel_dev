// Which data models get a generated public page, and what it may show.
//
// Every model has one unless it opts out, so this one decision is read by
// the model generator, the static-path manifest and the router alike. A model
// that did not ask for a page must never fail a build for want of one, and a
// model that stands for an account or a credential must never get one it did
// not ask for.
import 'package:dartvel_cli/src/generators/public_pages.dart';
import 'package:test/test.dart';

typedef Field = ({String type, String name});

DVPublicPages decide(
  String className,
  String args,
  List<Field> fields, {
  Set<String> sensitive = const <String>{},
}) =>
    DVPublicPages.of(
      className: className,
      modelArgs: args,
      fields: fields,
      sensitive: sensitive,
    );

const List<Field> article = <Field>[
  (type: 'String', name: 'slug'),
  (type: 'String', name: 'title'),
  (type: 'String', name: 'authorId'),
  (type: 'bool', name: 'published'),
  (type: 'String', name: 'editorNotes'),
];

void main() {
  group('by default', () {
    test('a model with nothing said gets a page keyed by its slug', () {
      final DVPublicPages pages = decide('Article', '', article);
      expect(pages.generates, isTrue);
      expect(pages.explicit, isFalse);
      expect(pages.keyField, 'slug');
      expect(pages.route, '/articles/:slug');
    });

    test('the route is the model name, plural and kebab-case', () {
      final DVPublicPages pages = decide('BlogPost', '',
          const <Field>[(type: 'String', name: 'id'), (type: 'String', name: 'title')]);
      expect(pages.route, '/blog-posts/:id');
      expect(decide('Category', '', const <Field>[(type: 'String', name: 'id')]).route,
          '/categories/:id');
    });

    test('generatePublicPages: false opts out, and says nothing', () {
      final DVPublicPages pages =
          decide('Article', 'generatePublicPages: false', article);
      expect(pages.generates, isFalse);
      expect(pages.skipped, isNull);
    });

    test('a model with no String field to key by is skipped with a note', () {
      final DVPublicPages pages = decide('Reading', '',
          const <Field>[(type: 'int', name: 'id'), (type: 'double', name: 'value')]);
      expect(pages.generates, isFalse);
      expect(pages.skipped, contains('no String field'));
      expect(pages.skipped, contains('generatePublicPages: false'));
    });

    test('a model whose key is sensitive is skipped: a key is in every URL', () {
      final DVPublicPages pages = decide(
          'Contact',
          'subject: DVSubject.field(\'ownerId\')',
          const <Field>[(type: 'String', name: 'email'), (type: 'String', name: 'ownerId')],
          sensitive: <String>{'email'});
      expect(pages.generates, isFalse);
      expect(pages.skipped, contains('email'));
    });

    test('a model keyed by the id of its privacy subject is skipped', () {
      final DVPublicPages pages = decide('Profile', 'subject: #userId',
          const <Field>[(type: 'String', name: 'userId'), (type: 'String', name: 'bio')]);
      expect(pages.generates, isFalse);
      expect(pages.skipped, contains('userId'));
    });

    test('a tenant-scoped model is skipped: a public page has no tenant', () {
      final DVPublicPages pages =
          decide('Invoice', 'tenantScoped: true', const <Field>[(type: 'String', name: 'id')]);
      expect(pages.generates, isFalse);
      expect(pages.skipped, contains('tenant'));
    });

    for (final String name in <String>[
      'User',
      'Account',
      'Session',
      'UserSession',
      'ApiToken',
      'RefreshToken',
      'ApiKey',
      'Credential',
      'Password',
      'PasswordReset',
      'Passkey',
      'ClientSecret',
      'AuditLog',
      'AuditEntry',
      'Audit',
      'Role',
      'Permission',
      'OneTimeCode',
      'RecoveryCode',
      'DVSomethingInternal',
    ]) {
      test('$name stands for an account, a credential or the framework, so no page',
          () {
        final DVPublicPages pages =
            decide(name, '', const <Field>[(type: 'String', name: 'id')]);
        expect(pages.generates, isFalse);
        expect(pages.skipped, contains('generatePublicPages: true'));
      });
    }

    for (final String name in <String>['Article', 'Tokenizer', 'Product', 'Roleplay', 'Userland']) {
      test('$name is not mistaken for one', () {
        expect(decide(name, '', const <Field>[(type: 'String', name: 'id')]).generates,
            isTrue);
      });
    }

    test('a row that is its own privacy subject is a person: no page', () {
      final DVPublicPages pages = decide('Customer', 'subject: DVSubject.self',
          const <Field>[(type: 'String', name: 'id'), (type: 'String', name: 'name')]);
      expect(pages.generates, isFalse);
      expect(pages.skipped, contains('subject'));
    });
  });

  group('asked for with generatePublicPages: true', () {
    test('an account model gets its page, and it is personal', () {
      final DVPublicPages pages = decide(
          'User',
          'generatePublicPages: true, subject: DVSubject.self',
          const <Field>[(type: 'String', name: 'slug'), (type: 'String', name: 'name')]);
      expect(pages.generates, isTrue);
      expect(pages.explicit, isTrue);
      expect(pages.personal, isTrue);
      expect(pages.protectedFields, containsAll(<String>['slug', 'name']));
    });

    test('a model with no key refuses the build, because a page was asked for', () {
      expect(
          () => decide('Reading', 'generatePublicPages: true',
              const <Field>[(type: 'int', name: 'id')]),
          throwsStateError);
    });

    test('a sensitive key refuses the build', () {
      expect(
          () => decide('Contact', 'generatePublicPages: true',
              const <Field>[(type: 'String', name: 'email')],
              sensitive: <String>{'email'}),
          throwsStateError);
    });

    test('a value the generator cannot read refuses the build', () {
      expect(() => decide('Article', 'generatePublicPages: kPages', article),
          throwsStateError);
    });
  });

  group('protected fields', () {
    test('are the sensitive fields and the fields naming the subject', () {
      final DVPublicPages pages = decide(
          'Article', 'subject: DVSubject.field(\'authorId\')', article,
          sensitive: <String>{'editorNotes'});
      expect(pages.protectedFields, <String>{'editorNotes', 'authorId'});
      expect(pages.personal, isFalse);
    });

    test('a subject symbol and a through path are read too', () {
      expect(decide('Article', 'subject: #authorId', article).protectedFields,
          <String>{'authorId'});
      expect(
          decide('Article',
                  'subject: DVSubject.through(\'authorId\', parent: \'Team\')', article)
              .protectedFields,
          <String>{'authorId'});
    });
  });

  group('a page the application writes itself', () {
    test('a paths resolver names the paths for the application\'s own page', () {
      final DVPublicPages pages =
          decide('Product', 'publicPathsResolver: productPaths', article);
      expect(pages.generates, isFalse);
      expect(pages.skipped, isNull);
    });

    test('a page file at the same route keeps it, and the model yields', () {
      final DVPublicPages pages = DVPublicPages.of(
        className: 'Article',
        modelArgs: '',
        fields: article,
        takenRoutes: <String>{'/articles/:id'},
      );
      expect(pages.generates, isFalse);
      expect(pages.skipped, contains('/articles/:slug'));
    });

    test('asked for by name, the model keeps its route', () {
      expect(
          DVPublicPages.of(
            className: 'Article',
            modelArgs: 'generatePublicPages: true',
            fields: article,
            takenRoutes: <String>{'/articles/:slug'},
          ).generates,
          isTrue);
    });
  });

  test('the published field is published, else isPublished, else none', () {
    expect(decide('Article', '', article).publishedField, 'published');
    expect(
        decide('Post', '', const <Field>[
          (type: 'String', name: 'id'),
          (type: 'bool', name: 'isPublished'),
        ]).publishedField,
        'isPublished');
    expect(decide('Post', '', const <Field>[(type: 'String', name: 'id')]).publishedField,
        isNull);
  });
}
