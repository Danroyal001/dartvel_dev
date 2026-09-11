// The builders are retired, and every one of them says so out loud.
//
// `auto_apply: dependents` means any project with dartvel_generator in its
// dependencies runs these builders, so the retirement cannot be announced only
// in a changelog: a user who never reads it would otherwise keep a path that
// cannot bootstrap a client on its own. They still generate exactly what they
// generated before -- a build that silently produced nothing would be worse
// than either keeping them or deleting them -- and each one logs a warning
// naming the command that replaces it.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dartvel_generator/dartvel_generator.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

const String pubspec = '''
name: a
dartvel:
  pagesDir: lib/pages
''';

const String loweredPage = r"""
import 'package:a/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

@DVPage(title: 'Home')
Widget _indexPage(BuildContext context) => const DVText('Home');
""";

/// Every record the builder logged, plus what it wrote.
Future<(List<LogRecord>, TestBuilderResult)> run(
  Builder builder,
  Map<String, String> sources,
) async {
  final List<LogRecord> records = <LogRecord>[];
  final TestBuilderResult result = await testBuilder(
    builder,
    <String, String>{'a|pubspec.yaml': pubspec, ...sources},
    rootPackage: 'a',
    onLog: records.add,
  );
  return (records, result);
}

List<LogRecord> retirementWarnings(List<LogRecord> records) => records
    .where((LogRecord r) => r.level >= Level.WARNING)
    .where((LogRecord r) => r.message.contains('retired'))
    .toList();

void expectSaysSo(List<LogRecord> records) {
  final List<LogRecord> warnings = retirementWarnings(records);
  expect(warnings, hasLength(1),
      reason: 'expected one retirement warning, got '
          '${records.map((LogRecord r) => '${r.level}: ${r.message}').toList()}');
  final String message = warnings.single.message;
  // The migration, not just the fact: a warning that does not name the
  // command that replaces it leaves the user with nowhere to go.
  expect(message, contains('dart run dartvel_cli:dartvel routes'));
  expect(message, contains('dartvel build'));
  // When it goes, so a user can plan rather than be surprised by a major.
  expect(message, contains('2.0.0'));
}

void main() {
  test('the router builder says the path is retired', () async {
    final (List<LogRecord> records, TestBuilderResult result) = await run(
      routerBuilder(BuilderOptions.empty),
      <String, String>{'a|lib/pages/index.dart': loweredPage},
    );
    expectSaysSo(records);
    // And still generates. A no-op that warns is a broken build with an
    // explanation, which is the one outcome worse than either choice.
    expect(result.outputs,
        contains(AssetId('a', 'lib/dartvel_client/router.g.dart')));
  });

  test('the page body builder says the path is retired', () async {
    final (List<LogRecord> records, TestBuilderResult result) = await run(
      pageBodyBuilder(BuilderOptions.empty),
      <String, String>{'a|lib/pages/index.dart': loweredPage},
    );
    expectSaysSo(records);
    expect(
      result.outputs,
      contains(AssetId('a', 'lib/dartvel_client/pages/pages/index.g.dart')),
    );
  });

  test('the route builder says the path is retired', () async {
    final (List<LogRecord> records, _) = await run(
      routeBuilder(BuilderOptions.empty),
      <String, String>{
        'a|lib/models/user.dart': 'class User {}\n',
      },
    );
    expectSaysSo(records);
  });

  test('once per build, not once per page', () async {
    // The page body builder runs on every file under lib/. A warning per
    // input buries every other message in a real project's build log.
    final (List<LogRecord> records, _) = await run(
      pageBodyBuilder(BuilderOptions.empty),
      <String, String>{
        'a|lib/pages/index.dart': loweredPage,
        'a|lib/pages/about.dart':
            loweredPage.replaceAll('_indexPage', '_aboutPage'),
        'a|lib/pages/contact.dart':
            loweredPage.replaceAll('_indexPage', '_contactPage'),
      },
    );
    expect(retirementWarnings(records), hasLength(1));
  });
}
