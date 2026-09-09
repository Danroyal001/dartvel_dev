// What `dartvel build linux-cli` generates for the binary it is about to
// produce.
//
// The build resolves the linked backends before it generates anything --
// resolveRenderBackends reads the -cli/-tui suffix and the dartvel.terminal
// key and returns the set -- and then threw the answer away. Generation ran as
// a subprocess with no way to be told, so the client generator worked it out
// again from `dartvel.terminal` alone, which is a different question.
//
// The consequences were both silent. `dartvel build linux-cli` on a project
// with no opt-in generated a main declaring DVRenderSurface.gui, in a binary
// that contains no GUI backend at all: nothing negotiates, nothing installs a
// terminal surface, and DV.Platform.surface reports a window that is not
// there. With the opt-in it generated the dual-mode main, whose terminal path
// looks for the -cli runner beside itself -- from inside the -cli runner.
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/generators/client_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Future<String> runtimeFor({
  bool terminalOptIn = false,
  Set<DVRenderBackend>? renderBackends,
}) async {
  final Directory root =
      await Directory.systemTemp.createTemp('dartvel_terminal_');
  addTearDown(() => root.deleteSync(recursive: true));

  Directory(p.join(root.path, 'lib', 'pages')).createSync(recursive: true);
  Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .createSync(recursive: true);
  File(p.join(root.path, 'lib', 'pages', 'index.page.dart')).writeAsStringSync(
    "import 'package:flutter/widgets.dart';\n"
    "import 'package:dartvel_flutter/dartvel_flutter.dart';\n"
    "@DVPage(title: 'Home')\n"
    "Widget _homePage(BuildContext context) => const DVText('hi');\n",
  );

  await ClientGenerator.generate(
    root: root.path,
    pagesDir: 'lib/pages',
    pkgName: 'term_app',
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
    webPrerender: false,
    ota: false,
    renderBackends: renderBackends,
    dv: terminalOptIn
        ? YamlMap.wrap(<String, Object?>{'terminal': true})
        : YamlMap(),
  );

  return Directory(p.join(root.path, 'lib', 'dartvel_client'))
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .map((File f) => f.readAsStringSync())
      .join('\n');
}

void main() {
  group('the wire format between build and generation', () {
    test('a resolved set survives the trip to the generator', () {
      for (final Set<DVRenderBackend> backends in <Set<DVRenderBackend>>[
        <DVRenderBackend>{DVRenderBackend.gui},
        <DVRenderBackend>{DVRenderBackend.terminal},
        <DVRenderBackend>{DVRenderBackend.gui, DVRenderBackend.terminal},
      ]) {
        expect(parseRenderBackends(renderBackendsFlag(backends)), backends);
      }
    });

    test('nothing said leaves the project to answer', () {
      // `dartvel routes` run by hand knows nothing about a suffix somebody
      // typed elsewhere. Answering GUI on its behalf would take the terminal
      // away from a project whose pubspec asked for it.
      expect(parseRenderBackends(null), isNull);
    });

    test('an untold generator still honours dartvel.terminal', () async {
      final String source = await runtimeFor(terminalOptIn: true);
      expect(
        source,
        contains('DVRenderSurface.gui, DVRenderSurface.terminal}'),
      );
    });

    test('a value nobody recognises is refused, not rounded down', () {
      // Rounding a typo down to the GUI is how a terminal build would quietly
      // generate a windowed main again, which is the whole defect.
      expect(() => parseRenderBackends('tui'), throwsFormatException);
      expect(() => parseRenderBackends(''), throwsFormatException);
      expect(
        () => parseRenderBackends('gui,graphical'),
        throwsFormatException,
      );
    });
  });

  group('a terminal-only build', () {
    test('links the terminal and nothing else', () async {
      final String source = await runtimeFor(
        renderBackends: <DVRenderBackend>{DVRenderBackend.terminal},
      );
      expect(source, contains('<DVRenderSurface>{DVRenderSurface.terminal}'));
      expect(source, isNot(contains('DVRenderSurface.gui')));
    });

    test('installs the surface it is drawing on', () async {
      // The only thing in a shipped application that ever produces a
      // DVTerminalGraphics. Without it DV.Platform.surface reports a GUI from
      // inside a terminal, and DV.Platform.terminal is null.
      final String source = await runtimeFor(
        renderBackends: <DVRenderBackend>{DVRenderBackend.terminal},
      );
      expect(source, contains('DV.Platform.useRenderSurface('));
      expect(source, contains('DVRenderSurface.terminal,'));
      expect(source, contains('terminal: await DVTerminalSurface.attach()'));
    });

    test('never goes looking for a terminal runner beside itself', () async {
      // It is that runner. Re-launching the -cli binary from the -cli binary
      // either fails on a name with two suffixes or spawns itself forever,
      // and both were reachable: the opt-in generated the dual-mode main and
      // the build produced it under the -cli name.
      final String source = await runtimeFor(
        terminalOptIn: true,
        renderBackends: <DVRenderBackend>{DVRenderBackend.terminal},
      );
      expect(source, isNot(contains('dvTerminalRunnerPathFor')));
      expect(source, isNot(contains('resolveLaunchSurface(')),
          reason: 'one backend, so there is no decision to make');
      expect(source, isNot(contains('dvTerminalFallbackPrompt')));
    });

    test('the opt-in does not add a GUI back', () async {
      // resolveRenderBackends already says the suffix is the stronger
      // statement; the generated main has to agree with it.
      final String source = await runtimeFor(
        terminalOptIn: true,
        renderBackends: <DVRenderBackend>{DVRenderBackend.terminal},
      );
      expect(source, isNot(contains('DVRenderSurface.gui')));
    });
  });

  group('the other two builds are unchanged', () {
    test('a GUI-only build negotiates nothing', () async {
      final String source = await runtimeFor();
      expect(source, contains('<DVRenderSurface>{DVRenderSurface.gui}'));
      expect(source, isNot(contains('DVRenderSurface.terminal')));
      expect(source, isNot(contains('DVTerminalSurface')));
    });

    test('a dual-mode build still decides at launch', () async {
      final String source = await runtimeFor(
        terminalOptIn: true,
        renderBackends: <DVRenderBackend>{
          DVRenderBackend.gui,
          DVRenderBackend.terminal,
        },
      );
      expect(source, contains('resolveLaunchSurface('));
      expect(source, contains('dvTerminalRunnerPathFor('));
      expect(
        source,
        contains('DVRenderSurface.gui, DVRenderSurface.terminal}'),
      );
    });
  });

  group('the build hands generation what it resolved', () {
    Future<List<String>> generationArgumentsFor(List<String> command) async {
      final Directory temp =
          Directory.systemTemp.createTempSync('dartvel_render_flag_');
      final Directory old = Directory.current;
      final List<String> invocations = <String>[];
      final BuildCommand build = BuildCommand(
        preflight: (String platform, {bool? autoInstall}) async => true,
        // Nothing is installed, so every target skips its actual build after
        // generation has already run. That is the part under test.
        onPath: (String _) => false,
        processRun: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          bool runInShell = false,
          Duration? timeout,
        }) async {
          invocations.add('$executable ${arguments.join(' ')}');
          return ProcessResult(0, 0, '', '');
        },
        hasBuildRunner: (String root) => false,
      );
      final runner = CommandRunner<void>('dartvel', 'test')..addCommand(build);
      try {
        Directory.current = temp;
        await runner.run(command);
      } finally {
        Directory.current = old;
        temp.deleteSync(recursive: true);
      }
      return invocations
          .where((String i) => i.contains('dartvel_cli:dartvel routes'))
          .toList();
    }

    test('a -cli target generates for the terminal', () async {
      expect(
        await generationArgumentsFor(<String>['build', 'linux-cli']),
        <String>['dart run dartvel_cli:dartvel routes --render terminal'],
      );
    });

    test('a -tui target is the same target', () async {
      expect(
        await generationArgumentsFor(<String>['build', 'linux-tui']),
        <String>['dart run dartvel_cli:dartvel routes --render terminal'],
      );
    });

    test('a plain desktop target generates for the GUI', () async {
      expect(
        await generationArgumentsFor(<String>['build', 'linux']),
        <String>['dart run dartvel_cli:dartvel routes --render gui'],
      );
    });
  });
}
