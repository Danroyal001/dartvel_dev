// @DVPolicy(ModelType) classes, which the specification says generate typed
// policy registries.
//
// The annotation existed, the specification gives it as the headline example
// of authorization, and nothing in the repository read it -- @DVPolicy
// appeared in exactly one file, the one declaring it. So a developer could
// write a PostPolicy, see it compile, and have every check answered by
// default-deny because nothing had ever registered it. It fails closed,
// which is the good direction, but a policy that is written and never
// consulted is an authorization model nobody has.
import 'dart:io';

import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Generates a project whose lib/policies/post_policy.dart is [source], and
/// returns the generated policies file.
Future<String> policiesFor(String source) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_policy_class_');
  addTearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });
  Directory(p.join(root.path, '.dart_tool')).createSync();
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'backend', 'functions'))
      .createSync(recursive: true);
  final Directory policiesDir = Directory(p.join(root.path, 'lib', 'policies'))
    ..createSync(recursive: true);
  File(p.join(policiesDir.path, 'post_policy.dart')).writeAsStringSync(source);

  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'policy_class_app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );

  return File(p.join(root.path, 'lib', 'dartvel_client', 'policies.g.dart'))
      .readAsStringSync();
}

const String _postPolicy = '''
import 'package:dartvel_core/dartvel.dart';

import '../models.dart';

@DVPolicy(Post)
class PostPolicy {
  bool update(User user, Post post) => post.authorId == user.id;
  bool delete(User user, Post post) => post.authorId == user.id;

  /// Not one of the conventional actions, so not registered.
  bool isAuthor(User user, Post post) => post.authorId == user.id;
}
''';

void main() {
  test('a policy class registers its conventional methods', () async {
    final String content = await policiesFor(_postPolicy);

    expect(content, contains("register('update'"));
    expect(content, contains("register('delete'"));
    expect(content, contains('PostPolicy'));
  });

  test('a method that is not a conventional action is left alone', () async {
    // The action names are the vocabulary the runtime answers questions in.
    // Registering a helper under its own name would put something in the
    // registry that nothing will ever ask for, and hide a typo: a method
    // named updaet would be registered rather than reported.
    final String content = await policiesFor(_postPolicy);

    expect(content, isNot(contains('isAuthor')));
  });

  test('the registration is typed by the method rather than by a cast',
      () async {
    // Registered with the method torn off, so Dart infers TUser and
    // TResource from its own signature. That is what makes the registry key
    // the resource type the policy actually takes, rather than a string this
    // generator assembled and could get wrong.
    final String content = await policiesFor(_postPolicy);

    expect(content, isNot(contains('as dynamic')));
    expect(content, isNot(contains('Object?')));
  });

  test('a project with no policy class registers nothing', () async {
    final String content = await policiesFor('''
import 'package:dartvel_core/dartvel.dart';

class NotAPolicy {
  bool update(Object user, Object post) => false;
}
''');

    expect(content, isNot(contains('register(')));
  });

  test('a policy whose method takes another type is refused', () async {
    // The silent version of this is the one worth stopping. The method is
    // registered under the type it takes, so a PostPolicy.update written
    // against Comment registers update:Comment -- Post keeps failing closed
    // while Comment is opened by a policy nobody wrote for it.
    await expectLater(
      policiesFor('''
import 'package:dartvel_core/dartvel.dart';

import '../models.dart';

@DVPolicy(Post)
class PostPolicy {
  bool update(User user, Comment comment) => false;
}
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(
            contains('post_policy.dart'),
            contains('update'),
            contains('Post'),
            contains('Comment'),
          ),
        ),
      ),
    );
  });

  test('a policy method that takes no resource is refused', () async {
    // Not a generator limitation: can(user, action, resource) always has a
    // resource, and the registry is keyed by its type, so a check that takes
    // only a user could never be reached by the question it answers.
    await expectLater(
      policiesFor('''
import 'package:dartvel_core/dartvel.dart';

import '../models.dart';

@DVPolicy(Post)
class PostPolicy {
  bool create(User user) => true;
}
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(
            contains('post_policy.dart'),
            contains('create'),
          ),
        ),
      ),
    );
  });

  test('a policy class that cannot be built with no arguments is refused',
      () async {
    // The generated file constructs one. A required argument would make it
    // fail to compile, which is a build error in a file nobody wrote and
    // cannot fix; saying so here names the file that has to change.
    await expectLater(
      policiesFor('''
import 'package:dartvel_core/dartvel.dart';

import '../models.dart';

@DVPolicy(Post)
class PostPolicy {
  PostPolicy(this.audit);

  final Object audit;

  bool update(User user, Post post) => false;
}
'''),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(
            contains('post_policy.dart'),
            contains('PostPolicy'),
          ),
        ),
      ),
    );
  });
}
