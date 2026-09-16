// dartvel.auth.deletionGraceDays, read at `dartvel routes` and written into
// account.g.dart for the generated server.
//
// What a deletion does with the window is account_deletion_grace_backend_test's.
// This pins the refusals: a grace period the build skipped or misread is a
// deletion that erases at once when the project said to wait, or one that
// waits past the erasure's own thirty-day deadline.
import 'package:dartvel_cli/src/generators/account_generator.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Map<Object?, Object?> _dv(String auth) => loadYaml('auth:\n$auth\n') as YamlMap;

void main() {
  test('nothing declared is no grace period: the deletion erases at once', () {
    expect(AccountGenerator.readDeletionGrace(const <Object?, Object?>{}), Duration.zero);
    expect(AccountGenerator.readDeletionGrace(_dv('  pages: false')), Duration.zero);
  });

  test('a whole number of days below the erasure deadline is the window', () {
    expect(AccountGenerator.readDeletionGrace(_dv('  deletionGraceDays: 7')),
        const Duration(days: 7));
    expect(AccountGenerator.readDeletionGrace(_dv('  deletionGraceDays: 0')),
        Duration.zero);
    expect(AccountGenerator.readDeletionGrace(_dv('  deletionGraceDays: 29')),
        const Duration(days: 29));
  });

  group('anything else stops the build, naming the key', () {
    for (final String value in <String>['-1', 'seven', '7.5', 'true', '"7"', '30', '90']) {
      test(value, () {
        expect(
          () => AccountGenerator.readDeletionGrace(_dv('  deletionGraceDays: $value')),
          throwsA(isA<StateError>().having((StateError e) => e.message, 'message',
              contains('dartvel.auth.deletionGraceDays'))),
        );
      });
    }

    test('and a window as long as the erasure deadline says why', () {
      expect(
        () => AccountGenerator.readDeletionGrace(_dv('  deletionGraceDays: 30')),
        throwsA(isA<StateError>().having(
            (StateError e) => e.message, 'message', contains('30-day'))),
      );
    });
  });

  test('account.g.dart installs the window the pubspec declared', () {
    final String source =
        AccountGenerator.render(appName: 'Bank', deletionGrace: const Duration(days: 7));
    expect(source, contains('const Duration dartvelAccountDeletionGrace = Duration(days: 7);'));
    expect(source, contains('DVAuthEndpoints.useDeletionGracePeriod(dartvelAccountDeletionGrace);'));
    expect(source, contains('DVAuthEndpoints.registerAccountErasureJob();'));
  });
}
