// Function mode: deploying each backend function on its own.
//
// `dartvel deploy` could push a web build to a hosting provider. The spec also
// lists function mode -- "each backend function can be deployed
// independently" to Lambda, Cloud Run, containers, edge runtimes, Fly, Railway
// or bare metal -- and none of it existed.
//
// Actually calling a cloud needs credentials. Producing the artifacts does
// not, and that is the part that is wrong or right regardless of who runs it:
// a handler name a provider rejects, a port the container never listens on, a
// manifest missing the function it was generated for.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/deploy/function_deploy.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVProcessConfiguration, DVProcessRole;
import 'package:test/test.dart';

const List<DVDeployableFunction> _functions = <DVDeployableFunction>[
  DVDeployableFunction(
    name: 'getUser',
    method: 'GET',
    path: '/api/users/:id',
    source: 'lib/backend/functions/users.get.dart',
  ),
  DVDeployableFunction(
    name: 'createOrder',
    method: 'POST',
    path: '/api/orders',
    source: 'lib/backend/functions/orders.dart',
  ),
];

void main() {
  group('choosing a target', () {
    test('an unknown target names the ones that exist', () {
      // Rather than producing nothing and reporting success, which is how a
      // typo becomes a deploy that quietly did not happen.
      expect(
        () => dvFunctionDeployPlan(
          functions: _functions,
          target: 'heroku',
          appName: 'shop',
        ),
        throwsA(isA<ArgumentError>().having(
          (ArgumentError e) => '${e.message}',
          'message',
          allOf(contains('lambda'), contains('cloud-run')),
        )),
      );
    });

    test('every documented target produces something', () {
      for (final String target in dvFunctionDeployTargets) {
        final DVFunctionDeployPlan plan = dvFunctionDeployPlan(
          functions: _functions,
          target: target,
          appName: 'shop',
        );
        expect(plan.files, isNotEmpty, reason: target);
      }
    });
  });

  group('lambda', () {
    late DVFunctionDeployPlan plan;
    setUp(() => plan = dvFunctionDeployPlan(
          functions: _functions,
          target: 'lambda',
          appName: 'shop',
        ));

    test('one deployment unit per function', () {
      // The point of function mode. One bundle for everything is monolith
      // mode wearing a different name.
      expect(plan.units, hasLength(2));
      expect(plan.units.map((DVDeployUnit u) => u.function.name),
          containsAll(<String>['getUser', 'createOrder']));
    });

    test('the function name is one a provider will accept', () {
      // Lambda allows letters, digits, hyphen and underscore, up to 64
      // characters. A route like /api/users/:id is none of those, and the
      // rejection arrives from the cloud rather than from here.
      for (final DVDeployUnit unit in plan.units) {
        expect(unit.remoteName, matches(RegExp(r'^[A-Za-z0-9_-]{1,64}$')),
            reason: unit.remoteName);
      }
    });

    test('two functions never collide on a name', () {
      final Set<String> names =
          plan.units.map((DVDeployUnit u) => u.remoteName).toSet();
      expect(names, hasLength(plan.units.length));
    });

    test('the manifest names every function it deploys', () {
      final String manifest = plan.files['dartvel-deploy.json']!;
      expect(manifest, contains('getUser'));
      expect(manifest, contains('createOrder'));
      expect(manifest, contains('lambda'));
    });
  });

  group('containers', () {
    test('the Dockerfile exposes the port the server binds', () {
      // A container that listens on one port and publishes another is a
      // deploy that starts cleanly and answers nothing.
      final DVFunctionDeployPlan plan = dvFunctionDeployPlan(
        functions: _functions,
        target: 'container',
        appName: 'shop',
        port: 8085,
      );

      final String dockerfile = plan.files['Dockerfile']!;
      expect(dockerfile, contains('EXPOSE 8085'));
      expect(dockerfile, contains('8085'));
    });

    test('cloud-run reads the port from the environment', () {
      // Cloud Run assigns PORT and a container that hardcodes one is marked
      // unhealthy and rolled back, with nothing in the logs to say why.
      final String dockerfile = dvFunctionDeployPlan(
        functions: _functions,
        target: 'cloud-run',
        appName: 'shop',
      ).files['Dockerfile']!;

      expect(dockerfile, contains(r'$PORT'));
    });
  });

  group('the runtime reads what the image sets', () {
    // Asserted by running the image's command -- with the server swapped for
    // env -- and reading the result through the backend's own resolver. An
    // `ENV DARTVEL_PORT=$PORT` line reads like the Cloud Run port and is
    // expanded when the image is built, when PORT is not set.
    Future<Map<String, String>> runtimeEnvironment(
      String dockerfile, [
      Map<String, String> container = const <String, String>{},
    ]) async {
      final Map<String, String> image = <String, String>{
        for (final String line in dockerfile.split('\n'))
          if (line.startsWith('ENV '))
            line.substring(4).split('=').first:
                line.substring(4).split('=').skip(1).join('='),
      };
      final String cmd =
          dockerfile.split('\n').singleWhere((String l) => l.startsWith('CMD '));
      final List<String> command = <String>[
        for (final Object? part in jsonDecode(cmd.substring(4)) as List<Object?>)
          '$part'.replaceAll('/app/server', '/usr/bin/env'),
      ];
      final ProcessResult result = await Process.run(
        command.first,
        command.sublist(1),
        includeParentEnvironment: false,
        environment: <String, String>{...image, ...container},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return <String, String>{
        for (final String line in '${result.stdout}'.split('\n'))
          if (line.contains('='))
            line.split('=').first: line.split('=').skip(1).join('='),
      };
    }

    DVProcessConfiguration resolve(Map<String, String> environment) =>
        // A generated port nobody would publish, so falling back to it fails.
        DVProcessConfiguration.resolve(
          environment: environment,
          generatedPort: 1,
        );

    for (final String target in <String>[
      'container',
      'railway',
      'bare-metal',
      'fly',
    ]) {
      test('$target: the port bound is the port exposed', () async {
        final String dockerfile = dvFunctionDeployPlan(
          functions: _functions,
          target: target,
          appName: 'shop',
          port: 8085,
        ).files['Dockerfile']!;
        expect(dockerfile, contains('EXPOSE 8085'));
        expect(resolve(await runtimeEnvironment(dockerfile)).port, 8085);
      });
    }

    test('cloud-run: the port bound is the one Cloud Run assigns at run time',
        () async {
      final String dockerfile = dvFunctionDeployPlan(
        functions: _functions,
        target: 'cloud-run',
        appName: 'shop',
      ).files['Dockerfile']!;
      final Map<String, String> environment = await runtimeEnvironment(
        dockerfile,
        const <String, String>{'PORT': '9123'},
      );
      expect(resolve(environment).port, 9123);
    });

    test('the image is one whole process unless a role is given', () async {
      final String dockerfile = dvFunctionDeployPlan(
        functions: _functions,
        target: 'container',
        appName: 'shop',
      ).files['Dockerfile']!;
      final DVProcessConfiguration alone =
          resolve(await runtimeEnvironment(dockerfile));
      expect(alone.role, DVProcessRole.web);
      expect(alone.ticksSchedules, isTrue);
      // The same image runs as a worker when the platform says so; the
      // image must not overwrite what the container was given.
      final DVProcessConfiguration worker = resolve(
        await runtimeEnvironment(
          dockerfile,
          const <String, String>{'DARTVEL_ROLE': 'worker'},
        ),
      );
      expect(worker.role, DVProcessRole.worker);
      expect(worker.servesHttp, isFalse);
    });
  });

  group('fly', () {
    test('the app name and internal port are set', () {
      final String toml = dvFunctionDeployPlan(
        functions: _functions,
        target: 'fly',
        appName: 'shop',
        port: 8080,
      ).files['fly.toml']!;

      expect(toml, contains('app = "shop"'));
      expect(toml, contains('internal_port = 8080'));
    });
  });

  group('what every plan carries', () {
    test('the secrets each function needs are declared, never valued', () {
      // A deployment descriptor is committed and read by CI. A value in one
      // is a value in the repository.
      final DVFunctionDeployPlan plan = dvFunctionDeployPlan(
        functions: _functions,
        target: 'lambda',
        appName: 'shop',
        secretNames: <String>{'PAYSTACK_SECRET'},
      );

      final String manifest = plan.files['dartvel-deploy.json']!;
      expect(manifest, contains('PAYSTACK_SECRET'));
      expect(manifest, isNot(contains('sk_')));
    });

    test('no functions is refused rather than producing an empty deploy', () {
      expect(
        () => dvFunctionDeployPlan(
          functions: const <DVDeployableFunction>[],
          target: 'lambda',
          appName: 'shop',
        ),
        throwsArgumentError,
      );
    });
  });
}
