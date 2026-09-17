// `dartvel deploy --store <store>`: a built application to a store or a
// tester group, on the command that already deploys a site and a server.
//
// The store form is the old `dartvel publish` moved, so the refusals it made
// still come before the upload. What is new is what it must refuse because
// deploy already had a meaning for it: a store is not a hosting provider,
// and "firebase" named Firebase Hosting on one command and App Distribution
// on the other.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/commands/deploy_command.dart';
import 'package:dartvel_cli/dartvel_impl.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _RecordingCloud extends DVCloudBuilder {
  final List<DVCloudBuildRequest> requests = <DVCloudBuildRequest>[];

  @override
  Future<int> run(DVCloudBuildRequest request) async {
    requests.add(request);
    return 0;
  }
}

/// Everything written to stdout inside the zone.
class _Capture implements Stdout {
  final StringBuffer out = StringBuffer();

  @override
  void writeln([Object? object = '']) => out.writeln(object);

  @override
  void write(Object? object) => out.write(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const String _play = '''
dartvel:
  publish:
    play:
      track: internal
      credentials: secrets/play.json
''';

void main() {
  late Directory root;
  late List<List<String>> ran;
  late _RecordingCloud cloud;
  late _Capture output;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_deploy_store_');
    ran = <List<String>>[];
    cloud = _RecordingCloud();
    output = _Capture();
    exitCode = 0;
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
  });

  void declare(String yaml) => File(
    p.join(root.path, 'pubspec.yaml'),
  ).writeAsStringSync('name: shopfront\n$yaml');

  void buildBundle() =>
      File(
          p.join(
            root.path,
            'build',
            'app',
            'outputs',
            'bundle',
            'release',
            'app-release.aab',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('a bundle');

  Future<ProcessResult> record(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    ran.add(<String>[executable, ...arguments]);
    return ProcessResult(0, 0, '', '');
  }

  Future<void> run(List<String> args) => IOOverrides.runZoned(
    () =>
        (CommandRunner<void>('dartvel', 'test')..addCommand(
              DeployCommand(
                processRun:
                    (
                      String executable,
                      List<String> arguments, {
                      bool runInShell = false,
                    }) => record(executable, arguments, runInShell: runInShell),
                root: root.path,
                cloud: cloud,
              ),
            ))
            .run(args),
    stdout: () => output,
  );

  group('deploy --store', () {
    test(
      'a dry run prints the upload and neither builds nor uploads',
      () async {
        declare(_play);
        buildBundle();

        await run(<String>['deploy', '--store', 'play', '--dry-run']);

        expect(exitCode, 0);
        // Not even the production build the web form starts with: a store
        // artifact is built by `dartvel build`, and a dry run changes nothing.
        expect(ran, isEmpty);
        expect(output.out.toString(), contains('fastlane supply --aab'));
      },
    );

    test(
      'a declaration the upload would refuse stops before anything runs',
      () async {
        declare(_play.replaceAll('      credentials: secrets/play.json\n', ''));
        buildBundle();

        await run(<String>['deploy', '--store', 'play']);

        expect(exitCode, 78);
        expect(ran, isEmpty);
      },
    );

    test('Firebase App Distribution is named in full', () async {
      declare(
        'dartvel:\n  publish:\n    firebase:\n      app: "1:1:android:ab"\n',
      );
      File(
          p.join(
            root.path,
            'build',
            'app',
            'outputs',
            'flutter-apk',
            'app-release.apk',
          ),
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('an apk');

      await run(<String>[
        'deploy',
        '--store',
        'firebase-app-distribution',
        '--dry-run',
      ]);

      expect(exitCode, 0);
      expect(output.out.toString(), contains('appdistribution:distribute'));
    });

    test(
      'a bare "firebase" is not a store: it would read as Hosting',
      () async {
        await expectLater(
          run(<String>['deploy', '--store', 'firebase']),
          throwsA(isA<UsageException>()),
        );
      },
    );

    test('--cloud sends the store the worker already knows', () async {
      declare(
        'dartvel:\n  publish:\n    firebase:\n      app: "1:1:android:ab"\n',
      );

      await run(<String>[
        'deploy',
        '--store',
        'firebase-app-distribution',
        '--cloud',
        '--dry-run',
        '--cloud-token',
        'tok',
      ]);

      expect(exitCode, 0);
      expect(ran, isEmpty);
      final DVCloudBuildRequest request = cloud.requests.single;
      // The wire name is unchanged, so a worker on the current protocol
      // takes the request as it took `publish firebase --cloud`.
      expect(
        (request.target, request.profile, request.publish, request.dryRun),
        ('android', 'release', 'firebase', true),
      );
      expect(request.token, 'tok');
    });

    test('--cloud builds an App Bundle for Play', () async {
      declare(_play);

      await run(<String>['deploy', '--store', 'play', '--cloud']);

      expect(exitCode, 0);
      final DVCloudBuildRequest request = cloud.requests.single;
      expect(
        (request.target, request.format, request.publish),
        ('android', 'aab', 'play'),
      );
    });

    for (final List<String> clash in <List<String>>[
      <String>['--provider', 'vercel'],
      <String>['--target', 'web'],
      <String>['--functions'],
      <String>['--function-target', 'lambda'],
    ]) {
      test(
        '--store with ${clash.first} is refused rather than half-honoured',
        () async {
          declare(_play);
          buildBundle();

          await expectLater(
            run(<String>['deploy', '--store', 'play', '--dry-run', ...clash]),
            throwsA(isA<UsageException>()),
          );
          expect(ran, isEmpty);
        },
      );
    }

    for (final List<String> storeOnly in <List<String>>[
      <String>['--dry-run'],
      <String>['--artifact', 'app.aab'],
      <String>['--cloud'],
      <String>['--cloud-token', 'tok'],
    ]) {
      test(
        '${storeOnly.first} without --store is refused, not ignored',
        () async {
          await expectLater(
            run(<String>['deploy', '--provider', 'vercel', ...storeOnly]),
            throwsA(isA<UsageException>()),
          );
          expect(ran, isEmpty);
          expect(cloud.requests, isEmpty);
        },
      );
    }
  });

  group('deploy --provider', () {
    test('firebase-hosting deploys Hosting', () async {
      await run(<String>[
        'deploy',
        '--no-build',
        '--target',
        'web',
        '--provider',
        'firebase-hosting',
      ]);

      expect(ran.last, <String>['firebase', 'deploy', '--only', 'hosting']);
    });

    test(
      'a bare firebase is refused, naming Hosting and App Distribution',
      () async {
        // Firebase is a host and a tester-distribution store; the bare word
        // is neither, so it is not guessed at.
        await expectLater(
          run(<String>[
            'deploy',
            '--no-build',
            '--target',
            'web',
            '--provider',
            'firebase',
          ]),
          throwsA(
            isA<UsageException>().having(
              (UsageException e) => e.message,
              'message',
              allOf(
                contains('--provider firebase-hosting'),
                contains('--store firebase-app-distribution'),
              ),
            ),
          ),
        );
        expect(ran, isEmpty);
      },
    );

    test('the help does not offer the bare firebase', () {
      expect(DeployCommand().argParser.usage, isNot(contains('[firebase]')));
    });
  });

  test('the help names every provider', () {
    final String usage = DeployCommand().argParser.usage;
    for (final String provider in <String>[
      'firebase-hosting',
      'vercel',
      'netlify',
      'cloudflare',
      'custom',
    ]) {
      expect(usage, contains(provider), reason: provider);
    }
  });

  group('there is no publish command', () {
    // Store submission is deploy --store. A second verb for it, even a
    // hidden one that forwards, is a second place to look for one thing.
    test('dartvel publish is not a registered command', () {
      expect(dartvelCommandRunner().commands.keys, isNot(contains('publish')));
    });

    test('dartvel publish is the unknown-command error', () async {
      await expectLater(
        dartvelCommandRunner().run(<String>['publish', 'play']),
        throwsA(
          isA<UsageException>().having(
            (UsageException e) => e.message,
            'message',
            contains('Could not find a command named "publish"'),
          ),
        ),
      );
    });

    test('modules publish, which signs a module, is a different command '
        'and stays', () {
      expect(
        dartvelCommandRunner().commands['modules']!.subcommands.keys,
        contains('publish'),
      );
    });
  });
}
