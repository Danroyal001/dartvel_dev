// The extension point for runtimes the framework does not ship: a package
// with a dartvel_runtimes.yaml that the generated client and backend install,
// and the refusal a free install gives when the project asks for one.
//
// Nothing here knows what a particular runtime does. The package under test
// is a fixture, which is the point: anyone can write one.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/build_targets.dart';
import 'package:dartvel_cli/src/build/runtime_packages.dart';
import 'package:dartvel_cli/src/commands/targets_command.dart';
import 'package:dartvel_cli/src/config/dartvel_config.dart';
import 'package:dartvel_cli/src/generators/backend_generator.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const String _manifest = '''
runtimes: [telegram, terminal]
client:
  import: package:acme_runtimes/acme_runtimes.dart
  install: dvInstallAcmeRuntimes
  terminal_surface: AcmeTerminal.attach()
server:
  import: package:acme_runtimes/server.dart
  auth_providers:
    telegram: acmeTelegramAuthProvider()
''';

/// A project directory whose package_config names a runtime package whose
/// manifest is [manifest] (none when null).
Directory _project({String? manifest = _manifest, String dartvel = ''}) {
  final Directory root = Directory.systemTemp.createTempSync('dv_runtimes_');
  addTearDown(() => root.deleteSync(recursive: true));
  final Directory package = Directory(p.join(root.path, 'acme_runtimes'))
    ..createSync();
  if (manifest != null) {
    File(p.join(package.path, dvRuntimeManifestFile)).writeAsStringSync(manifest);
  }
  Directory(p.join(root.path, '.dart_tool')).createSync();
  File(p.join(root.path, '.dart_tool', 'package_config.json')).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'acme_runtimes',
          'rootUri': '../acme_runtimes',
          'packageUri': 'lib/',
        },
      ],
    }),
  );
  File(p.join(root.path, 'pubspec.yaml'))
      .writeAsStringSync('name: app\nenvironment:\n  sdk: ^3.13.0\n$dartvel');
  return root;
}

Future<String> _clientSource(
  Directory root, {
  Set<DVRenderBackend>? renderBackends,
  Map<String, Object?> dartvel = const <String, Object?>{},
}) async {
  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n",
  );
  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    devBackendHost: 'http://localhost:3000',
    prodBackendHost: 'https://example.com',
    apiBasePath: '/api',
    envFiles: const <String>[],
    seoSiteName: 'app',
    seoTitle: 'app',
    seoDesc: 'app',
    seoImage: '',
    seoTwitter: '',
    defaultTransition: 'none',
    durationMs: 200,
    curve: 'linear',
    normalizeTrailing: true,
    notFoundRedirect: '/',
    plugins: const <String>[],
    ota: false,
    renderBackends: renderBackends,
    dv: YamlMap.wrap(dartvel),
  );
  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

Future<String> _backendSource(Directory root) async {
  Directory(p.join(root.path, 'lib', 'backend', 'functions')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client')).createSync(recursive: true);
  await BackendGenerator.generate(
    root: root.path,
    backendDir: 'lib/backend',
    pkgName: 'app',
    buildId: 'test-build',
    backendHost: '127.0.0.1',
    backendPort: 3000,
    apiBasePath: '/api',
  );
  return Directory(p.join(root.path, '.dart_tool'))
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  group('finding a runtime package', () {
    test('reads the manifest of a dependency', () {
      final DVRuntimePackage package = dvRuntimePackages(_project().path).single;
      expect(package.name, 'acme_runtimes');
      expect(package.runtimes, <String>['telegram', 'terminal']);
      expect(package.clientImport, 'package:acme_runtimes/acme_runtimes.dart');
      expect(package.clientInstall, 'dvInstallAcmeRuntimes');
      expect(package.terminalSurface, 'AcmeTerminal.attach()');
      expect(package.serverImport, 'package:acme_runtimes/server.dart');
      expect(package.authProviders, <String, String>{'telegram': 'acmeTelegramAuthProvider()'});
    });

    test('finds nothing before pub get, without a manifest, or with a broken one', () {
      expect(dvRuntimePackages(Directory.systemTemp.createTempSync().path), isEmpty);
      expect(dvRuntimePackages(_project(manifest: null).path), isEmpty);
      expect(dvRuntimePackages(_project(manifest: ': : not yaml').path), isEmpty);
      expect(dvRuntimePackages(_project(manifest: 'name: x').path), isEmpty);
    });

    test('names the package that provides a runtime', () {
      final Directory root = _project();
      expect(dvRuntimePackageFor(root.path, 'telegram')?.name, 'acme_runtimes');
      expect(dvRuntimePackageFor(root.path, 'xr'), isNull);
    });
  });

  group('refusing a runtime the install does not have', () {
    test('dartvel.telegram without a provider says what it is and how to get it', () {
      final Directory root = _project(manifest: null);
      final String? refusal = dvRuntimeRefusalFor(root.path, <String, Object?>{'telegram': <String, Object?>{}});
      expect(refusal, isNotNull);
      expect(refusal, contains('dartvel.telegram'));
      expect(refusal, contains('paid runtime'));
      expect(refusal, contains('dartvel targets add runtimes'));
      expect(refusal, contains('0.11.5'));
      expect(refusal, contains('Every free target'));
    });

    test('is silent when a package provides it, and when nothing asks', () {
      expect(
        dvRuntimeRefusalFor(_project().path, <String, Object?>{'telegram': <String, Object?>{}}),
        isNull,
      );
      expect(dvRuntimeRefusalFor(_project(manifest: null).path, <String, Object?>{}), isNull);
      expect(dvRuntimeRefusalFor(_project(manifest: null).path, null), isNull);
    });
  });

  group('public configuration for a runtime', () {
    test('server secrets cannot be declared in it', () async {
      final Directory root = _project(manifest: null, dartvel: 'dartvel:\n  telegram:\n    botToken: secret\n');
      await expectLater(DartvelConfig.load(root), throwsFormatException);
    });

    test('a section without secrets is carried as it was written', () async {
      final Directory root = _project(dartvel: 'dartvel:\n  telegram:\n    botUsername: acme_bot\n');
      final DartvelConfig config = await DartvelConfig.load(root);
      expect(config.telegram, <String, Object?>{'botUsername': 'acme_bot'});
    });
  });

  group('the generated client', () {
    test('installs every runtime package with the sections the project wrote', () async {
      final String source = await _clientSource(
        _project(),
        dartvel: <String, Object?>{'telegram': <String, Object?>{'botUsername': 'acme_bot'}},
      );
      expect(source, contains("import 'package:acme_runtimes/acme_runtimes.dart' as acme_runtimes;"));
      expect(source, contains('acme_runtimes.dvInstallAcmeRuntimes('));
      expect(source, contains("'telegram'"));
    });

    test('links nothing when no runtime package is a dependency', () async {
      final String source = await _clientSource(_project(manifest: null));
      expect(source, isNot(contains('acme_runtimes')));
      expect(source, isNot(contains('DVTelegram')));
    });

    test('a terminal-only build attaches the surface the package supplies', () async {
      final String source = await _clientSource(
        _project(),
        renderBackends: <DVRenderBackend>{DVRenderBackend.terminal},
      );
      expect(source, contains('attached: await acme_runtimes.AcmeTerminal.attach()'));
      expect(source, isNot(contains('DVTerminalSurface')));
    });

    test('a terminal-only build with no package that supplies one is refused', () async {
      await expectLater(
        _clientSource(
          _project(manifest: null),
          renderBackends: <DVRenderBackend>{DVRenderBackend.terminal},
        ),
        throwsA(isA<FormatException>().having((FormatException e) => e.message, 'message', contains('paid runtime'))),
      );
    });
  });

  group('the generated backend', () {
    test('installs the sign-in provider the package supplies for a configured section', () async {
      final String source = await _backendSource(
        _project(dartvel: 'dartvel:\n  telegram:\n    botUsername: acme_bot\n'),
      );
      expect(source, contains("import 'package:acme_runtimes/server.dart' as acme_runtimes;"));
      expect(source, contains('provider: acme_runtimes.acmeTelegramAuthProvider()'));
    });

    test('installs none for a project that configured no section', () async {
      final String source = await _backendSource(_project());
      expect(source, isNot(contains('acmeTelegramAuthProvider')));
    });

    test('refuses a configured section nothing provides a provider for', () async {
      await expectLater(
        _backendSource(_project(manifest: null, dartvel: 'dartvel:\n  telegram:\n    botUsername: acme_bot\n')),
        throwsA(isA<FormatException>().having((FormatException e) => e.message, 'message', contains('paid runtime'))),
      );
    });
  });

  test('dartvel targets add runtimes adds the runtimes package as a dependency', () async {
    final Directory root = _project(manifest: null);
    final List<String> ran = <String>[];
    final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
      ..addCommand(TargetsCommand(
        root: root.path,
        processRun: (String executable, List<String> arguments, {String? workingDirectory}) async {
          ran.add('$executable ${arguments.join(' ')}');
          return ProcessResult(0, 0, '', '');
        },
      ));
    await runner.run(<String>['targets', 'add', 'runtimes']);
    expect(ran.single, contains('pub add $dvRuntimesProPackage:'));
    expect(ran.single, isNot(contains('dev:')));
    expect(ran.single, contains('packages/dartvel_runtimes_pro'));
  });
}
