// The resolution order the specification states is the process environment,
// then .env for local development, then values supplied by configure. The
// runtime only ever did the first and the last, and nothing said so.
//
// That gap had teeth beyond a missing convenience. `dartvel deploy` gates on
// whether every required secret resolves, and it resolved names against the
// process environment *and* a .env file it parsed itself -- with a comment
// claiming that was the same order the runtime used. So a project keeping its
// staging credentials in .env passed the gate and then threw
// DVSecretNotFoundException on the first request that needed one. A green
// check for a deploy that cannot work is worse than no check.
@TestOn('vm')
library;

// Aliased: the dartvel barrel exports a Platform of its own, and an
// unqualified reference here would silently pick the wrong one.
import 'dart:io' as io;

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late io.Directory tmp;

  setUp(() {
    DVSecrets.reset();
    tmp = io.Directory.systemTemp.createTempSync('dartvel_dotenv_');
  });

  tearDown(() {
    DVSecrets.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  io.File writeEnv(String contents) {
    final io.File file = io.File('${tmp.path}/.env')..writeAsStringSync(contents);
    DVSecrets.useEnvFile(file.path);
    return file;
  }

  group('.env resolution', () {
    test('a value only in .env resolves', () {
      writeEnv('PAYSTACK_SECRET=sk_test_localdev123\n');

      expect(const DVSecrets().get('PAYSTACK_SECRET'), 'sk_test_localdev123');
    });

    test('the process environment wins over .env', () {
      // A stale checked-in .env must never shadow what the operator set on
      // the machine actually running the process. That direction is how a
      // production deploy quietly picks up a development credential.
      final String name = io.Platform.environment.keys.first;
      writeEnv('$name=from_the_dotenv_file\n');

      expect(
        const DVSecrets().get(name),
        io.Platform.environment[name],
      );
    });

    test('configure still wins over both', () {
      // DV.Test.withSecrets depends on this. A developer with the variable
      // exported in their shell would otherwise break a suite that supplied
      // its own value, which is the thing withSecrets exists to prevent.
      writeEnv('API_TOKEN=from_the_dotenv_file\n');
      DVSecrets.configure(<String, String>{'API_TOKEN': 'from_configure'});

      expect(const DVSecrets().get('API_TOKEN'), 'from_configure');
    });

    test('comments and blank lines are skipped', () {
      writeEnv('''
# a comment mentioning KEY=not_this

REAL_KEY=real_value_here
''');

      expect(const DVSecrets().get('REAL_KEY'), 'real_value_here');
      expect(const DVSecrets().maybeGet('KEY'), isNull);
    });

    test('quotes around a value are not part of it', () {
      writeEnv('QUOTED="value with spaces"\nSINGLE=\'other value\'\n');

      expect(const DVSecrets().get('QUOTED'), 'value with spaces');
      expect(const DVSecrets().get('SINGLE'), 'other value');
    });

    test('an export prefix is accepted', () {
      // People paste these files into a shell. A line the shell reads and the
      // framework silently ignores is a secret that is set everywhere except
      // where the code looks.
      writeEnv('export SHELL_STYLE=works_anyway\n');

      expect(const DVSecrets().get('SHELL_STYLE'), 'works_anyway');
    });

    test('an empty assignment counts as absent', () {
      // `KEY=` through a shell is what an unset variable looks like, and a
      // payment client configured with the empty string fails a long way from
      // the cause.
      writeEnv('BLANK=\n');

      expect(const DVSecrets().has('BLANK'), isFalse);
    });

    test('a missing .env is not an error', () {
      DVSecrets.useEnvFile('${tmp.path}/nothing-here.env');

      expect(const DVSecrets().maybeGet('ANYTHING'), isNull);
    });

    test('a value from .env is redacted from logs like any other', () {
      writeEnv('DATABASE_PASSWORD=local-dev-password-9\n');
      const DVSecrets().get('DATABASE_PASSWORD');

      final DVMemoryLogSink sink = DVMemoryLogSink();
      DVLogger(sinks: <DVLogSink>[sink])
          .info('connecting with local-dev-password-9');

      expect(
        sink.records.single.message,
        isNot(contains('local-dev-password-9')),
      );
    });

    test('reset puts the file back to the default', () {
      writeEnv('SCOPED=only_for_this_test\n');
      expect(const DVSecrets().has('SCOPED'), isTrue);

      DVSecrets.reset();

      expect(const DVSecrets().has('SCOPED'), isFalse);
    });

    test('a rewritten file is picked up rather than served from a cache', () {
      // Parsed once and remembered, or every read touches the disk. Whichever
      // it is, pointing at a new file has to mean the new file.
      writeEnv('ROTATING=first_value_here\n');
      expect(const DVSecrets().get('ROTATING'), 'first_value_here');

      final io.File other = io.File('${tmp.path}/second.env')
        ..writeAsStringSync('ROTATING=second_value_here\n');
      DVSecrets.useEnvFile(other.path);

      expect(const DVSecrets().get('ROTATING'), 'second_value_here');
    });
  });
}
