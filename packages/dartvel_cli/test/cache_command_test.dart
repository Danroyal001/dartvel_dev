import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/cache_command.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('CacheCommand', () {
    late CommandRunner<void> runner;

    setUp(() {
      const DVTestHarness().resetCacheTags();
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(CacheCommand());
    });

    test('inspect reads keys for a cache tag', () async {
      const tags = DVCacheTags();
      tags.tag('users:list', <String>['users']);

      await runner.run(<String>['cache', 'inspect', 'users']);

      expect(tags.keysForTag('users'), contains('users:list'));
    });

    test('revalidate removes keys for a cache tag', () async {
      const tags = DVCacheTags();
      tags.tag('users:list', <String>['users']);

      await runner.run(<String>['cache', 'revalidate', 'users']);

      expect(tags.keysForTag('users'), isEmpty);
    });

    test('clear resets cache tag metadata', () async {
      const tags = DVCacheTags();
      tags.tag('users:list', <String>['users']);

      await runner.run(<String>['cache', 'clear']);

      expect(tags.keysForTag('users'), isEmpty);
    });
  });
}
