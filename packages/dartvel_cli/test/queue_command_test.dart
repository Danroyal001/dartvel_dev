import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/queue_command.dart';
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  group('QueueCommand', () {
    late CommandRunner<void> runner;

    setUp(() {
      const DVTestHarness().resetQueues();
      runner = CommandRunner<void>('dartvel', 'Test runner')
        ..addCommand(QueueCommand());
    });

    test('work command processes queued jobs', () async {
      final processed = <String>[];
      const queues = DVQueues();
      queues.register<String>(processed.add);
      await queues.dispatch<String>('mail', queue: 'mail');

      await runner.run(<String>['queue', 'work', '--queue', 'mail']);

      expect(processed, <String>['mail']);
      expect(await queues.pending('mail'), isEmpty);
    });

    test('retry command moves dead-lettered jobs back to pending', () async {
      const queues = DVQueues();
      await queues.dispatch<int>(7, maxAttempts: 1);
      await runner.run(<String>['queue', 'work']);

      final failed = await queues.deadLetters();
      expect(failed, hasLength(1));

      await runner.run(<String>['queue', 'retry', failed.single.id]);

      expect(await queues.deadLetters(), isEmpty);
      expect(await queues.pending(), hasLength(1));
    });

    test('flush command removes pending and failed jobs', () async {
      const queues = DVQueues();
      await queues.dispatch<String>('pending');
      await queues.dispatch<int>(1, maxAttempts: 1);
      await runner.run(<String>['queue', 'work']);

      await runner.run(<String>['queue', 'flush']);

      expect(await queues.pending(), isEmpty);
      expect(await queues.deadLetters(), isEmpty);
    });
  });
}
