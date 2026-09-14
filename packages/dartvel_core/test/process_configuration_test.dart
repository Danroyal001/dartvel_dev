// What a backend process is told to be, read from its environment.
//
// One built binary runs as the web server, a queue worker or the schedules.
// The quiet failures this guards: a DARTVEL_PORT that does not parse, silently
// replaced by the generated port -- so the second instance on a host crash
// loops on a taken port, or a container listens on a port nobody publishes;
// a misspelt role that starts a web server; a worker or a web instance in a
// cluster that also ticks the schedules, firing each one once per process.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVProcessConfiguration resolve(
  Map<String, String> environment, {
  List<String> arguments = const <String>[],
}) => DVProcessConfiguration.resolve(
  environment: environment,
  arguments: arguments,
  generatedPort: 8080,
);

Matcher refusedNaming(String text) => throwsA(
  isA<DVProcessConfigurationError>().having(
    (DVProcessConfigurationError e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  group('port', () {
    test('the generated port when DARTVEL_PORT is not set', () {
      expect(resolve(const <String, String>{}).port, 8080);
    });

    test('DARTVEL_PORT wins over the generated port', () {
      expect(
        resolve(const <String, String>{'DARTVEL_PORT': '8081'}).port,
        8081,
      );
    });

    for (final String bad in <String>[
      'abc',
      '',
      ' 8081',
      '8081 ',
      '80.5',
      '-1',
      '0',
      '65536',
      '99999999999999999999',
      '0x50',
      '+8081',
    ]) {
      test('"$bad" refuses to start rather than falling back', () {
        expect(
          () => resolve(<String, String>{'DARTVEL_PORT': bad}),
          refusedNaming('DARTVEL_PORT'),
        );
      });
    }

    test('the edges of the range are ports', () {
      expect(resolve(const <String, String>{'DARTVEL_PORT': '1'}).port, 1);
      expect(
        resolve(const <String, String>{'DARTVEL_PORT': '65535'}).port,
        65535,
      );
    });

    test('a malformed port refuses a worker too: the deployment is wrong', () {
      expect(
        () => resolve(const <String, String>{
          'DARTVEL_ROLE': 'worker',
          'DARTVEL_PORT': 'eighty',
        }),
        refusedNaming('DARTVEL_PORT'),
      );
    });
  });

  group('role', () {
    test('a process told nothing is the web server, and ticks schedules', () {
      final DVProcessConfiguration c = resolve(const <String, String>{});
      expect(c.role, DVProcessRole.web);
      expect(c.roleDeclared, isFalse);
      expect(c.servesHttp, isTrue);
      // One process is the whole deployment: nothing else would run them.
      expect(c.ticksSchedules, isTrue);
    });

    test('a declared web process does not tick: a cron process does', () {
      final DVProcessConfiguration c = resolve(const <String, String>{
        'DARTVEL_ROLE': 'web',
      });
      expect(c.role, DVProcessRole.web);
      expect(c.servesHttp, isTrue);
      expect(c.ticksSchedules, isFalse);
    });

    test('a worker serves nothing and ticks nothing', () {
      final DVProcessConfiguration c = resolve(const <String, String>{
        'DARTVEL_ROLE': 'worker',
      });
      expect(c.role, DVProcessRole.worker);
      expect(c.servesHttp, isFalse);
      expect(c.ticksSchedules, isFalse);
      expect(c.queues, <String>['default']);
    });

    test('cron ticks and serves nothing', () {
      final DVProcessConfiguration c = resolve(const <String, String>{
        'DARTVEL_ROLE': 'cron',
      });
      expect(c.role, DVProcessRole.cron);
      expect(c.servesHttp, isFalse);
      expect(c.ticksSchedules, isTrue);
    });

    for (final String bad in <String>[
      'backend',
      'Worker',
      'crons',
      '',
      'web ',
    ]) {
      test('"$bad" is refused, naming the roles', () {
        expect(
          () => resolve(<String, String>{'DARTVEL_ROLE': bad}),
          refusedNaming('web, worker, cron'),
        );
      });
    }

    test('--role selects it as well, in either spelling', () {
      expect(
        resolve(
          const <String, String>{},
          arguments: <String>['--role=cron'],
        ).role,
        DVProcessRole.cron,
      );
      expect(
        resolve(
          const <String, String>{},
          arguments: <String>['--role', 'worker'],
        ).role,
        DVProcessRole.worker,
      );
      expect(
        resolve(
          const <String, String>{},
          arguments: <String>['--role=web'],
        ).ticksSchedules,
        isFalse,
      );
    });

    test('an argument and a variable that disagree are refused', () {
      expect(
        () => resolve(
          const <String, String>{'DARTVEL_ROLE': 'web'},
          arguments: <String>['--role=cron'],
        ),
        refusedNaming('DARTVEL_ROLE'),
      );
    });

    test('--role with no value is refused', () {
      expect(
        () => resolve(const <String, String>{}, arguments: <String>['--role']),
        refusedNaming('--role'),
      );
    });
  });

  group('queues', () {
    test('DARTVEL_QUEUE names what a worker works', () {
      expect(
        resolve(const <String, String>{
          'DARTVEL_ROLE': 'worker',
          'DARTVEL_QUEUE': 'mail',
        }).queues,
        <String>['mail'],
      );
      expect(
        resolve(const <String, String>{
          'DARTVEL_ROLE': 'worker',
          'DARTVEL_QUEUE': 'default,mail',
        }).queues,
        <String>['default', 'mail'],
      );
    });

    for (final String bad in <String>[
      '',
      'mail,',
      ',mail',
      'mail,,sms',
      'a b',
    ]) {
      test('"$bad" is refused rather than working a queue nobody named', () {
        expect(
          () => resolve(<String, String>{
            'DARTVEL_ROLE': 'worker',
            'DARTVEL_QUEUE': bad,
          }),
          refusedNaming('DARTVEL_QUEUE'),
        );
      });
    }

    test('a queue named for a process that works none is refused', () {
      // A unit that says DARTVEL_QUEUE=mail on a web process was meant to
      // be a worker; serving HTTP instead is how mail stops going out.
      expect(
        () => resolve(const <String, String>{'DARTVEL_QUEUE': 'mail'}),
        refusedNaming('DARTVEL_QUEUE'),
      );
    });
  });
}
