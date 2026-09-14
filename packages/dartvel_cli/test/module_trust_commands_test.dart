// The commands in front of module trust: `dartvel modules publish`,
// `dartvel modules pin`, `dartvel doctor --modules`, and the gate
// `dartvel build` runs before it generates anything.
//
// What matters is the failure path. A publish that refuses must not reach
// `dart pub publish`, and a build whose modules do not verify must stop before
// generation -- a refusal that is printed and then carried on from is the log
// line and green exit this section exists to replace.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/build/declaration_check.dart';
import 'package:dartvel_cli/src/commands/doctor_command.dart';
import 'package:dartvel_cli/src/commands/modules_command.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:dartvel_cli/src/module_trust/module_publish.dart';
import 'package:dartvel_cli/src/module_trust/package_digest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Uint8List publisherKey = Uint8List.fromList(
  List<int>.generate(32, (int i) => i + 1),
);

const String _code = '''
Future<void> charge() async {
  final String key = DV.Secrets.get('STRIPE_KEY');
  await DV.Http.post('https://api.stripe.com/v1/charges', json: <String, Object?>{'k': key});
}
''';

String _modulePubspec(String version) =>
    'name: acme_payments\n'
    'version: $version\n'
    'dartvel:\n'
    '  module:\n'
    '    capabilities:\n'
    '      secrets: [STRIPE_KEY]\n'
    "      egress: ['api.stripe.com']\n";

const String _grant = '''
      grant:
        secrets: [STRIPE_KEY]
        egress: ['api.stripe.com']
''';

class Project {
  Project(this.root);

  final Directory root;
  String get path => root.path;
  String get module => p.join(path, 'modules', 'payments');
  String get keyFile => p.join(path, 'publisher.key');
}

Project project({String grant = _grant, String code = _code}) {
  final Directory root = Directory.systemTemp.createTempSync(
    'dartvel_modtrust_cmd_',
  );
  addTearDown(() => root.deleteSync(recursive: true));
  final Project project = Project(root);
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
    'name: shopfront\n'
    'dartvel:\n'
    '  modules:\n'
    '    payments:\n'
    '      mount: /pay\n'
    '      package: acme_payments\n'
    '$grant',
  );
  File(p.join(project.module, 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_modulePubspec('2.1.0'));
  File(p.join(project.module, 'lib', 'payments.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(code);
  File(p.join(root.path, '.dart_tool', 'package_config.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'acme_payments',
            'rootUri': '../modules/payments',
            'packageUri': 'lib/',
          },
        ],
      }),
    );
  File(project.keyFile).writeAsStringSync(base64Url.encode(publisherKey));
  return project;
}

class Recorded {
  final List<String> invocations = <String>[];
  final List<String?> directories = <String?>[];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell = false,
  }) async {
    invocations.add(<String>[executable, ...arguments].join(' '));
    directories.add(workingDirectory);
    return ProcessResult(0, 0, '', '');
  }
}

Future<void> modules(String root, List<String> args, {Recorded? process}) =>
    (CommandRunner<void>('dartvel', 'test')
          ..addCommand(ModulesCommand(root: root, processRun: process?.call)))
        .run(<String>['modules', ...args]);

void main() {
  late int savedExitCode;
  setUp(() {
    savedExitCode = exitCode;
    exitCode = 0;
  });
  tearDown(() => exitCode = savedExitCode);

  group('dartvel modules publish', () {
    test(
      'signs the module, then hands over to dart pub publish in it',
      () async {
        final Project p0 = project();
        final Recorded process = Recorded();
        await modules(p0.module, <String>[
          'publish',
          '--key',
          p0.keyFile,
          '--key-id',
          'acme-2026',
          '--publisher',
          'acme.example',
        ], process: process);

        expect(exitCode, 0);
        expect(
          File(p.join(p0.module, dvModuleSignatureFile)).existsSync(),
          isTrue,
        );
        expect(process.invocations, <String>['dart pub publish']);
        expect(process.directories, <String?>[p0.module]);
      },
    );

    test('--dry-run is passed to pub rather than skipping it', () async {
      final Project p0 = project();
      final Recorded process = Recorded();
      await modules(p0.module, <String>[
        'publish',
        '--key',
        p0.keyFile,
        '--key-id',
        'acme-2026',
        '--dry-run',
      ], process: process);
      expect(process.invocations, <String>['dart pub publish --dry-run']);
    });

    test('--sign-only writes the signature and publishes nothing', () async {
      final Project p0 = project();
      final Recorded process = Recorded();
      await modules(p0.module, <String>[
        'publish',
        '--key',
        p0.keyFile,
        '--key-id',
        'acme-2026',
        '--sign-only',
      ], process: process);
      expect(
        File(p.join(p0.module, dvModuleSignatureFile)).existsSync(),
        isTrue,
      );
      expect(process.invocations, isEmpty);
    });

    test('a refused publish never reaches pub', () async {
      final Project p0 = project(code: '$_code\nfinal c = HttpClient();\n');
      final Recorded process = Recorded();
      await modules(p0.module, <String>[
        'publish',
        '--key',
        p0.keyFile,
        '--key-id',
        'acme-2026',
      ], process: process);
      expect(exitCode, isNot(0));
      expect(process.invocations, isEmpty);
      expect(
        File(p.join(p0.module, dvModuleSignatureFile)).existsSync(),
        isFalse,
      );
    });

    test('there is no unsigned publish', () async {
      final Project p0 = project();
      final Recorded process = Recorded();
      await expectLater(
        modules(p0.module, <String>['publish'], process: process),
        throwsA(isA<UsageException>()),
      );
      expect(process.invocations, isEmpty);
    });
  });

  group('dartvel modules pin', () {
    test('writes the lockfile', () async {
      final Project p0 = project();
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin']);
      expect(exitCode, 0);
      expect(DVModuleLock.read(p0.path).pins.keys, <String>['acme_payments']);
    });

    test('pins only the modules named', () async {
      final Project p0 = project();
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin', 'somethingelse']);
      expect(File(p.join(p0.path, dvModuleLockFile)).existsSync(), isFalse);
    });

    test('refuses a downgrade unless --allow-downgrade says so', () async {
      final Project p0 = project();
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin']);

      File(
        p.join(p0.module, 'pubspec.yaml'),
      ).writeAsStringSync(_modulePubspec('2.0.0'));
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );

      await modules(p0.path, <String>['pin']);
      expect(exitCode, isNot(0));
      expect(
        DVModuleLock.read(p0.path).pins['acme_payments']!.version,
        '2.1.0',
      );

      exitCode = 0;
      await modules(p0.path, <String>['pin', '--allow-downgrade']);
      expect(exitCode, 0);
      expect(
        DVModuleLock.read(p0.path).pins['acme_payments']!.version,
        '2.0.0',
      );
    });

    test(
      'an unsigned dependency fails the command and writes nothing',
      () async {
        final Project p0 = project();
        await modules(p0.path, <String>['pin']);
        expect(exitCode, isNot(0));
        expect(File(p.join(p0.path, dvModuleLockFile)).existsSync(), isFalse);
      },
    );
  });

  group('dartvel doctor --modules', () {
    Future<void> doctor(String root) =>
        (CommandRunner<void>('dartvel', 'test')
              ..addCommand(DoctorCommand(root: root)))
            .run(<String>['doctor', '--modules']);

    test('fails when a module uses what the parent did not grant', () async {
      final Project p0 = project(grant: '');
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin']);
      exitCode = 0;
      await doctor(p0.path);
      expect(exitCode, isNot(0));
    });

    test('passes when every pin verifies and every use is granted', () async {
      final Project p0 = project();
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin']);
      await doctor(p0.path);
      expect(exitCode, 0);
    });
  });

  // `dartvel build` refuses to start on DVDeclarationCheck, before anything
  // is generated, and exits the process when it does -- so the gate is
  // asserted on the check rather than by running a build that would take the
  // test runner down with it.
  group('dartvel build refuses to start', () {
    test('when a module was changed after it was pinned', () async {
      final Project p0 = project();
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin']);
      File(
        p.join(p0.module, 'lib', 'payments.dart'),
      ).writeAsStringSync('$_code\n// changed after it was pinned\n');

      final DVDeclarationCheck check = DVDeclarationCheck.run(p0.path);
      expect(check.ok, isFalse);
      expect(check.lines.join('\n'), contains('DV-MODULE-004'));
    });

    test('when a module uses what the parent did not grant', () async {
      final Project p0 = project(grant: '');
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin']);

      final DVDeclarationCheck check = DVDeclarationCheck.run(p0.path);
      expect(check.ok, isFalse);
      expect(check.lines.join('\n'), contains('DV-MODULE-001'));
    });

    test('when a dependency was never pinned', () {
      final Project p0 = project();
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      expect(DVDeclarationCheck.run(p0.path).ok, isFalse);
    });

    test('and not when every module verifies and is granted', () async {
      final Project p0 = project();
      dvPrepareModulePublish(
        p0.module,
        privateKey: publisherKey,
        keyId: 'acme-2026',
      );
      await modules(p0.path, <String>['pin']);

      final DVDeclarationCheck check = DVDeclarationCheck.run(p0.path);
      expect(check.ok, isTrue, reason: check.lines.join('\n'));
    });
  });
}
