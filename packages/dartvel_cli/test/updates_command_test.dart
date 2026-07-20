import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/updates_command.dart';
import 'package:test/test.dart';

void main() {
  group('UpdatesCommand', () {
    late CommandRunner<void> runner;

    setUp(() {
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(UpdatesCommand());
    });

    test('release supports dry-run for target platforms', () async {
      await runner.run(<String>[
        'updates',
        'release',
        '--platform',
        'android',
        '--dry-run',
      ]);
    });

    test('patch supports release-version and dry-run', () async {
      await runner.run(<String>[
        'updates',
        'patch',
        '--platform',
        'ios',
        '--release-version',
        '1.2.3',
        '--dry-run',
      ]);
    });

    test('push remains a patch alias for existing scripts', () async {
      await runner.run(<String>[
        'updates',
        'push',
        '--platform',
        'android',
        '--release-version',
        '1.2.3',
        '--dry-run',
      ]);
    });

    test('rollback supports Shorebird patch track dry-run', () async {
      await runner.run(<String>[
        'updates',
        'rollback',
        '--release-version',
        '1.2.3',
        '--patch-number',
        '4',
        '--dry-run',
      ]);
    });
  });
}
