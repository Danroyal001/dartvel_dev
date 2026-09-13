// `@DVFlags()` declarations become the typed `Flags` accessors.
//
// The reason flags are generated at all is that a flag named by a string is a
// flag that can be misspelt, and a misspelt flag does not throw — it misses,
// and answers its default for ever. So the generated surface is asserted on,
// and so is the one thing the generator must refuse: a flag with no expiry,
// because a flag is debt with an owner and a date on it.
import 'dart:io';

import 'package:dartvel_cli/src/generators/flag_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes [source] as `lib/flags/flags.dart`, generates, and returns the
/// generated `flags.g.dart` with the warnings the pass produced.
Future<(String, List<String>)> generate(String source, {DateTime? now}) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_flag_test_');
  try {
    Directory(p.join(root.path, 'lib', 'flags')).createSync(recursive: true);
    File(p.join(root.path, 'lib', 'flags', 'flags.dart'))
        .writeAsStringSync(source);

    final List<String> warnings = await FlagGenerator.generate(
      root: root.path,
      pkgName: 'flag_app',
      buildId: 'test-build',
      now: now ?? DateTime.utc(2026, 9, 1),
    );

    return (
      File(p.join(root.path, 'lib', 'dartvel_client', 'flags.g.dart'))
          .readAsStringSync(),
      warnings,
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}

const String declared = '''
import 'package:dartvel_core/dartvel.dart';

enum Recommender { baseline, embeddings }

@DVFlags()
abstract class _Flags {
  /// The rewritten checkout. Kill switch for the payments team.
  @DVFlag(owner: 'payments', expires: '2026-12-01')
  static const bool newCheckout = false;

  @DVFlag(owner: 'search', expires: '2026-11-01', settle: DVFlagSettle.onNextLaunch)
  static const String recommender = 'baseline';

  @DVFlag(owner: 'feed', expires: '2027-02-01')
  static const int pageSize = 20;

  @DVFlag(owner: 'obs', expires: '2027-02-01')
  static const double sampleRate = 0.25;

  @DVFlag(owner: 'search', expires: '2027-02-01')
  static const Recommender kind = Recommender.baseline;
}
''';

void main() {
  test('each declared flag becomes a typed accessor with its metadata',
      () async {
    final (String generated, List<String> _) = await generate(declared);

    expect(generated, contains('abstract final class Flags {'));
    expect(
      generated,
      contains('static final DVFeatureFlag<bool> newCheckout = '
          'DVFeatureFlag<bool>('),
    );
    expect(generated, contains("key: 'newCheckout',"));
    expect(generated, contains('defaultValue: false,'));
    expect(generated, contains("owner: 'payments',"));
    expect(generated, contains('expires: DateTime.utc(2026, 12, 1),'));

    expect(generated, contains('DVFeatureFlag<String> recommender'));
    expect(generated, contains('settle: DVFlagSettle.onNextLaunch,'));
    expect(generated, contains('DVFeatureFlag<int> pageSize'));
    expect(generated, contains('defaultValue: 20,'));
    expect(generated, contains('DVFeatureFlag<double> sampleRate'));
    expect(generated, contains('defaultValue: 0.25,'));

    // The doc comment travels, so the accessor explains itself on hover.
    expect(generated,
        contains('/// The rewritten checkout. Kill switch for the payments team.'));
  });

  test('an enum flag reads its values from the declaring file', () async {
    final (String generated, List<String> _) = await generate(declared);

    expect(generated, contains("import 'package:flag_app/flags/flags.dart'"));
    expect(generated, contains('Recommender.values'));
    expect(generated, contains('Recommender.baseline'));
  });

  test('every flag is declared to the runtime, so unknown rules are noticed',
      () async {
    final (String generated, List<String> _) = await generate(declared);

    expect(generated, contains('static final List<DVFeatureFlag<Object?>> all'));
    for (final String name in <String>[
      'newCheckout',
      'recommender',
      'pageSize',
      'sampleRate',
      'kind',
    ]) {
      expect(generated, contains('    $name,'));
    }
    expect(generated, contains('void registerDartvelFlags()'));
    expect(generated, contains('DVFlags.declare(Flags.all);'));
  });

  test('a project with no flags still gets a valid, empty surface', () async {
    final (String generated, List<String> warnings) =
        await generate("void main() {}\n");

    expect(generated, contains('abstract final class Flags {'));
    expect(generated, contains('<DVFeatureFlag<Object?>>[]'));
    expect(warnings, isEmpty);
  });

  test('a flag with no expiry is refused', () async {
    await expectLater(
      generate('''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
abstract class _Flags {
  @DVFlag(owner: 'payments')
  static const bool newCheckout = false;
}
'''),
      throwsA(isA<StateError>().having(
          (StateError e) => e.message, 'message', contains('expires'))),
    );
  });

  test('a public @DVFlags class is refused: generation inputs are private',
      () async {
    await expectLater(
      generate('''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
abstract class Flags {
  @DVFlag(owner: 'payments', expires: '2026-12-01')
  static const bool newCheckout = false;
}
'''),
      throwsA(isA<StateError>().having(
          (StateError e) => e.message, 'message', contains('private'))),
    );
  });

  test('a type a flag cannot carry is refused', () async {
    await expectLater(
      generate('''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
abstract class _Flags {
  @DVFlag(owner: 'payments', expires: '2026-12-01')
  static const Map<String, int> tiers = <String, int>{};
}
'''),
      throwsA(isA<StateError>().having(
          (StateError e) => e.message, 'message', contains('type'))),
    );
  });

  test('a flag past its expiry warns with DV-FLAGS-004', () async {
    final (String _, List<String> warnings) =
        await generate(declared, now: DateTime.utc(2026, 12, 2));

    expect(warnings, hasLength(2),
        reason: 'newCheckout and recommender are both past due on 2 Dec');
    expect(warnings.join('\n'), contains('DV-FLAGS-004'));
    expect(warnings.join('\n'), contains('newCheckout'));
    expect(warnings.join('\n'), contains('payments'));
  });

  // A private declaration nothing can reference draws unused_element and
  // unused_field, and the repository's answer for private generation inputs is
  // @pragma('vm:entry-point'). A generator that stopped recognising the class
  // or the field once that pragma is added would make the flags silently
  // vanish from Flags — the fix for a warning turning into a missing flag.
  test('a pragma on the class or a field does not hide a flag', () async {
    for (final String source in <String>[
      '''
import 'package:dartvel_core/dartvel.dart';

@DVFlags()
@pragma('vm:entry-point')
abstract class _Flags {
  @DVFlag(owner: 'payments', expires: '2099-12-01')
  @pragma('vm:entry-point')
  static const bool newCheckout = false;
}
''',
      '''
import 'package:dartvel_core/dartvel.dart';

@pragma('vm:entry-point')
@DVFlags()
abstract class _Flags {
  @pragma('vm:entry-point')
  @DVFlag(owner: 'payments', expires: '2099-12-01')
  static const bool newCheckout = false;
}
''',
    ]) {
      final (String generated, List<String> _) = await generate(source);
      expect(generated, contains('DVFeatureFlag<bool> newCheckout'),
          reason: 'the pragma must not stop the flag being generated:\n$source');
    }
  });
}
