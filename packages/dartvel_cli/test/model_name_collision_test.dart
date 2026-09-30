// A data model may be called Post, or Route.
//
// A blog has posts and a delivery app has routes, and those are the names
// their data models want. Both are also names the generated client sees from
// somewhere else: `Post`, `Get`, `Put`, `Delete`, `Patch` and `Route` are
// dartvel_core's HTTP annotations, and `Route` is Flutter's too. The model is
// declared in models.g.dart, which imports all of them unprefixed, and every
// other generated file imports models.g.dart beside them -- so a name the
// generated code wrote bare became ambiguous there, and the application got a
// client that did not compile for having picked an ordinary word.
//
// The fix is in the generated code, not in a list of names a model may not
// have. So this generates a project with a model named Post and one named
// Route, analyzes the lot against the real packages, and then runs a widget
// test inside it that builds, fills and reads back both models' forms --
// compiling is not the same as working.
//
// Post also carries a sensitive field, so the same run proves that the form
// generated for a real model never shows one.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dartvel_cli/src/generators/routes_generator.dart' as routes;
import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _post = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel(
  subject: DVSubject.field('authorId'),
  retain: DVRetention.indefinite,
  generatePublicPages: true,
)
class const _Post({
  required final String slug,
  required final String authorId,
  @DVModel.pageTitle() required final String title,
  @DVModel.mainContent() required final String body,
  @DVModel.sensitiveField() required final String moderatorNotes,
  required final int likes,
});
''';

const String _route = '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class const _Route({
  required final String id,
  required final String origin,
  required final String destination,
  required final int stops,
});
''';

/// The page an application writes: both models by name, through the barrel,
/// beside Flutter's own widgets library.
const String _page = '''
import 'package:flutter/widgets.dart' hide Route;

import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Home')
@pragma('vm:entry-point')
Widget _indexPage(BuildContext context) => DVBox.list(<Widget>[
      Post.Form(),
      Route.Form(),
      const Post(slug: 'a', authorId: 'u', title: 'A', body: 'B', moderatorNotes: 'x', likes: 0).Form(),
      Post.List(const <Post>[]),
      Route.Table(const <Route>[]),
    ]);
''';

/// A backend function that takes and returns the models, so the generated
/// functions, their client and their codecs name them too.
const String _backend = '''
import '../../dartvel_client/dartvel_client.dart';

@DVBackendFunction()
@pragma('vm:entry-point')
Future<Post?> _firstPost(String slug) async => Post.find(slug);

''';

const String _backendRoute = '''
import '../../dartvel_client/dartvel_client.dart';

@DVBackendFunction()
@pragma('vm:entry-point')
Future<Route?> _firstRoute(String id) async => Route.find(id);
''';

/// Runs inside the generated project, against the generated client.
const String _widgetTest = r'''
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:collision_probe/dartvel_client/dartvel_client.dart';

// Compiled, not run: the generated client functions return the models. Before
// the fix firstPost returned dartvel_core's @Post annotation, which has no
// slug -- a client that compiled and typed every result wrongly.
Future<String?> postSlug() async =>
    (await firstPost(slug: 's', fromJson: (Object? json) => null))?.slug;
Future<String?> routeOrigin() async =>
    (await firstRoute(id: 'r', fromJson: (Object? json) => null))?.origin;

void main() {
  setUpAll(registerDartvelModels);

  Future<Map<String, String>> fieldsOf(WidgetTester tester, Widget form) async {
    await tester.pumpWidget(MaterialApp(home: Material(child: form)));
    await tester.pumpAndSettle();
    final Map<String, String> byLabel = <String, String>{};
    for (final Element e in find.byType(TextField).evaluate()) {
      final TextField field = e.widget as TextField;
      byLabel[field.decoration?.labelText ?? ''] =
          field.controller?.text ?? '';
    }
    return byLabel;
  }

  testWidgets('Post.Form() has an input per public field, and none for the '
      'sensitive one', (WidgetTester tester) async {
    final Map<String, String> fields = await fieldsOf(tester, Post.Form());
    expect(fields.keys, containsAll(<String>['SLUG', 'AUTHORID', 'TITLE', 'BODY', 'LIKES']));
    expect(fields.keys, isNot(contains('MODERATORNOTES')));
  });

  testWidgets('editing a Post neither shows nor prefills its sensitive field',
      (WidgetTester tester) async {
    const Post post = Post(
      slug: 'hello',
      authorId: 'u',
      title: 'Hello',
      body: 'World',
      moderatorNotes: 'flagged by legal',
      likes: 0,
    );
    await tester.pumpWidget(MaterialApp(home: Material(child: post.Form())));
    await tester.pumpAndSettle();
    expect(find.textContaining('flagged by legal'), findsNothing);
    expect(find.text('hello'), findsWidgets);
  });

  testWidgets('no other generated view of a Post shows the sensitive field',
      (WidgetTester tester) async {
    const Post post = Post(
      slug: 'hello',
      authorId: 'u',
      title: 'Hello',
      body: 'World',
      moderatorNotes: 'flagged by legal',
      likes: 0,
    );
    for (final Widget view in <Widget>[
      Post.Card(post),
      Post.List(const <Post>[post]),
      Post.Table(const <Post>[post]),
      Post.PageBody(post),
    ]) {
      await tester.pumpWidget(
          MaterialApp(home: Material(child: SingleChildScrollView(child: view))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Hello'), findsWidgets,
          reason: '${view.runtimeType} should show the record');
      expect(find.textContaining('flagged by legal'), findsNothing,
          reason: '${view.runtimeType} showed a sensitive field');
    }
  });

  testWidgets('Route.Form() is a working form for a model named Route',
      (WidgetTester tester) async {
    final Map<String, String> fields = await fieldsOf(tester, Route.Form());
    expect(fields.keys,
        containsAll(<String>['ID', 'ORIGIN', 'DESTINATION', 'STOPS']));
  });

  test('a Route and a Post round-trip through their generated codecs', () {
    const Route route = Route(id: 'r1', origin: 'A', destination: 'B', stops: 2);
    expect(RouteParser.fromJson(route.toJson()).stops, 2);
    const Post post =
        Post(slug: 's', authorId: 'u', title: 't', body: 'b', moderatorNotes: 'm', likes: 3);
    expect(PostParser.fromJson(post.toJson()).likes, 3);
    expect(post.toPublicJson().containsKey('moderatorNotes'), isFalse);
  });
}
''';

Future<String> repoRoot() async {
  final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dartvel_cli/dartvel_cli.dart'));
  if (lib == null) {
    throw StateError('dartvel_cli could not resolve its own package URI.');
  }
  return p.normalize(p.join(p.dirname(lib.toFilePath()), '..', '..', '..'));
}

void write(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void main() {
  late Directory project;
  late ProcessResult analysis;

  setUpAll(() async {
    final root = await repoRoot();
    project = await Directory.systemTemp.createTemp('dartvel_collision_');
    write(p.join(project.path, 'analysis_options.yaml'),
        ProjectTemplates.analysisOptionsTemplate);
    write(p.join(project.path, 'lib', 'models', 'post.dart'), _post);
    write(p.join(project.path, 'lib', 'models', 'route.dart'), _route);
    write(p.join(project.path, 'lib', 'pages', 'index.page.dart'), _page);
    write(p.join(project.path, 'lib', 'backend', 'functions', 'first_post.dart'),
        _backend);
    write(p.join(project.path, 'lib', 'backend', 'functions', 'first_route.dart'),
        _backendRoute);
    write(p.join(project.path, 'test', 'collision_test.dart'), _widgetTest);
    write(p.join(project.path, 'pubspec.yaml'), '''
name: collision_probe
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  flutter:
    sdk: flutter
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
dev_dependencies:
  flutter_test:
    sdk: flutter
dartvel:
  prodBackendHost: https://example.com
''');
    write(p.join(project.path, 'pubspec_overrides.yaml'), '''
dependency_overrides:
  dartvel_core:
    path: ${p.join(root, 'packages', 'dartvel_core')}
  dartvel_flutter:
    path: ${p.join(root, 'packages', 'dartvel_flutter')}
  dartvel_shelf:
    path: ${p.join(root, 'packages', 'dartvel_shelf')}
''');

    await routes.generate(root_: project.path);

    final resolved = await Process.run('flutter', <String>['pub', 'get'],
        workingDirectory: project.path);
    if (resolved.exitCode != 0) {
      throw StateError('flutter pub get failed:\n${resolved.stderr}');
    }
    analysis = await Process.run(
      'flutter',
      <String>['analyze', 'lib', 'test'],
      workingDirectory: project.path,
    );
  });

  tearDownAll(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  List<String> errors() => const LineSplitter()
      .convert('${analysis.stdout}${analysis.stderr}')
      .where((String line) => line.contains('error •'))
      .toList(growable: false);

  test('the models were generated under the names they were given', () {
    final String models = File(p.join(
            project.path, 'lib', 'dartvel_client', 'models.g.dart'))
        .readAsStringSync();
    expect(models, contains(RegExp(r'class (const )?Post\b')));
    expect(models, contains(RegExp(r'class (const )?Route\b')));
    expect(analysis.exitCode, anyOf(0, 1),
        reason: 'flutter analyze did not run: ${analysis.stderr}');
  });

  test('a project with data models named Post and Route compiles', () {
    expect(errors(), isEmpty,
        reason: 'the generated client must compile:\n${errors().join('\n')}');
  });

  test('and the generated client is warning-clean doing it', () {
    // Hiding a model's name from a framework library that never exported it
    // draws undefined_hidden_name; the generated files ignore that one, and
    // nothing else may appear.
    final List<String> warnings = const LineSplitter()
        .convert('${analysis.stdout}${analysis.stderr}')
        .where((String line) => line.contains('warning •'))
        .where((String line) => line.contains('dartvel_client'))
        .toList(growable: false);
    expect(warnings, isEmpty, reason: warnings.join('\n'));
  });

  test('and its models work: forms, codecs, and no sensitive field in the '
      'form', () async {
    final ProcessResult run = await Process.run(
      'flutter',
      <String>['test', 'test/collision_test.dart'],
      workingDirectory: project.path,
    );
    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
