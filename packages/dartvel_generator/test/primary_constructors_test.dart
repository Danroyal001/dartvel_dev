// The retired builders still run in every project that depends on this
// package, and those projects are now written with primary constructors:
// `class const Layout({super.key, required super.child}) extends
// DartvelLayout`. The route builder resolves each library with the analyzer,
// and an analyzer that predates Dart 3.13 cannot parse that declaration --
// "This requires the 'primary-constructors' language feature to be enabled"
// -- so a project on the retired path stopped building the moment it adopted
// the syntax its own scaffold writes.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dartvel_generator/dartvel_generator.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

const String pubspec = '''
name: a
environment:
  sdk: ">=3.13.0 <4.0.0"
dartvel:
  pagesDir: lib/pages
''';

void main() {
  test('a library written with primary constructors is still read', () async {
    final List<LogRecord> records = <LogRecord>[];
    await testBuilder(
      routeBuilder(BuilderOptions.empty),
      <String, String>{
        'a|pubspec.yaml': pubspec,
        'a|lib/screens/home.dart': '''
class const HomeScreen(final String title, {final int visits = 0}) {
  String get label => '\$title (\$visits)';
}
''',
      },
      rootPackage: 'a',
      onLog: records.add,
    );

    final List<String> errors = <String>[
      for (final LogRecord r in records)
        if (r.level >= Level.SEVERE) r.message,
    ];
    expect(errors, isEmpty);
  });
}
