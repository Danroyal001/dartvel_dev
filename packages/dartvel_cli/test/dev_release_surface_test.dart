import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/dev_command.dart';
import 'package:dartvel_cli/src/commands/deploy_command.dart';
import 'package:dartvel_cli/src/commands/preview_command.dart';
import 'package:test/test.dart';

void main() {
  for (final flags in <List<String>>[
    ['--preview', '--list', '--destroy'],
    ['--preview', '--provider', 'custom'],
    ['--preview', '--store', 'play'],
    ['--preview', '--dry-run'],
    ['--preview', '--follow'],
    ['--list'],
    ['--from-pr', '412'],
    ['--preview', '--environment', 'production'],
    ['--preview', '--no-build'],
    ['--preview', '--no-verify'],
    ['--preview', '--functions'],
    ['--preview', '--list', '--from-pr', '412'],
    ['--preview', '--list', '--branch', 'feature/cart'],
    ['--preview', '--closed-pr', '412'],
    ['--preview', '--sweep', '--branch', 'feature/cart'],
    ['--preview', 'destroy'],
  ]) {
    test('refuses ambiguous or misplaced deployment flags: $flags', () async {
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(DeployCommand());
      await expectLater(
        runner.run(['deploy', ...flags]),
        throwsA(isA<UsageException>()),
      );
    });
  }

  for (final flags in <List<String>>[
    ['--release', '--device', 'linux'],
    ['--release', '--debug'],
    ['--release', '--profile'],
    ['--release', '--web-port', '8080'],
    ['--release', '--dart-define', 'A=B'],
    ['--release', '--pairing-port', '8787'],
    ['--release', '--port', 'not-a-port'],
    ['--release', '--port', '65536'],
    ['--release', '--port', '-1'],
    ['--port', '8080'],
  ]) {
    test('refuses incompatible release-serving flags: $flags', () async {
      final runner = CommandRunner<void>('dartvel', 'test')
        ..addCommand(DevCommand());
      await expectLater(
        runner.run(['dev', ...flags]),
        throwsA(isA<UsageException>()),
      );
    });
  }

  test('release serving accepts the existing host and port options', () {
    final args = DevCommand().argParser.parse([
      '--release',
      '--host',
      '127.0.0.1',
      '-p',
      '9090',
    ]);
    expect(args['release'], isTrue);
    expect(args['host'], '127.0.0.1');
    expect(args['port'], '9090');
  });
  test('branch deployments accept their lifecycle flags', () {
    for (final action in ['list', 'open', 'logs', 'destroy', 'sweep']) {
      final args = DeployCommand().argParser.parse(['--preview', '--$action']);
      expect(args['preview'], isTrue);
      expect(args[action], isTrue);
    }
  });
  test('compatibility command is absent from top-level help', () {
    final runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(DevCommand())
      ..addCommand(DeployCommand())
      ..addCommand(PreviewCommand());
    expect(
      runner.usage,
      isNot(matches(RegExp(r'^\s+preview\s', multiLine: true))),
    );
    expect(runner.commands.containsKey('preview'), isTrue);
  });
}
