// Targets the CLI does not build itself: the paid ones, refused with a way to
// get them on a free install, and any target a package registers through
// DVBuildTarget, which the build runs through the CLI's own pipeline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_cli/build_targets.dart';
import 'package:dartvel_cli/src/build/target_packages.dart';
import 'package:dartvel_cli/src/cloud/cloud_build.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:dartvel_cli/src/commands/doctor_command.dart';
import 'package:dartvel_cli/src/commands/targets_command.dart';
import 'package:test/test.dart';

class _RecordingCloud extends DVCloudBuilder {
  final List<DVCloudBuildRequest> requests = <DVCloudBuildRequest>[];

  @override
  Future<int> run(DVCloudBuildRequest request) async {
    requests.add(request);
    return 0;
  }
}

/// A target that records what it was handed.
class _FakeTarget extends DVBuildTarget {
  _FakeTarget(this.name, {this.result = DVBuildTargetResult.succeeded});

  @override
  final String name;
  final DVBuildTargetResult result;
  final List<DVBuildTargetContext> contexts = <DVBuildTargetContext>[];

  @override
  String get summary => 'a fake target';

  @override
  bool availableOn(String hostOs) => true;

  @override
  Set<DVRenderBackend>? get renderBackends =>
      name.endsWith('-term') ? const <DVRenderBackend>{DVRenderBackend.terminal} : null;

  @override
  Future<DVBuildTargetResult> build(DVBuildTargetContext context) async {
    contexts.add(context);
    return result;
  }
}

/// A target riding on the web pipeline with a variant.
class _VariantTarget extends DVBuildTarget {
  final List<String> events = <String>[];

  @override
  String get name => 'web-variant';

  @override
  String get summary => 'the web build, adjusted';

  @override
  String get basePlatform => 'web';

  @override
  bool availableOn(String hostOs) => true;

  @override
  Future<DVBuildTargetResult> build(DVBuildTargetContext context) =>
      context.buildPlatform(
        'web',
        variant: DVPlatformVariant(
          name: name,
          flutterArguments: const <String>['--dart-define=DARTVEL_PLATFORM=web-variant'],
          prepare: (DVBuildTargetContext context) {
            events.add('prepare');
            return true;
          },
          finish: (DVBuildTargetContext context, {required bool built}) {
            events.add('finish built=$built');
            return true;
          },
        ),
      );
}

/// A process that has already exited with [code] and printed nothing.
class _ExitedProcess implements Process {
  _ExitedProcess(this.code);
  final int code;

  @override
  Future<int> get exitCode async => code;
  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();
  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);
  @override
  int get pid => 0;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

void main() {
  late Directory root;
  late List<String> invocations;
  late List<String> output;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dartvel_build_targets_');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: shop\n');
    invocations = <String>[];
    output = <String>[];
    exitCode = 0;
    DVBuildTargets.clear();
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    exitCode = 0;
    DVBuildTargets.clear();
  });

  Future<void> run(List<String> args,
      {DVCloudBuilder? cloud,
      BuildProcessStart? processStart,
      bool preflight = true}) async {
    final StringBuffer printed = StringBuffer();
    await IOOverrides.runZoned(
      () => (CommandRunner<void>('dartvel', 'test')
            ..addCommand(BuildCommand(
              root: root.path,
              cloud: cloud,
              processStart: processStart,
              preflight: (String platform, {bool? autoInstall}) async {
                invocations.add('preflight $platform');
                return preflight;
              },
              processRun: (String executable, List<String> arguments,
                  {String? workingDirectory, bool runInShell = false}) async {
                invocations.add('$executable ${arguments.join(' ')}');
                return ProcessResult(0, 0, '', '');
              },
              hasBuildRunner: (String _) => false,
            )))
          .run(<String>['build', ...args]),
      stdout: () => _BufferStdout(printed),
    );
    output = const LineSplitter().convert(printed.toString());
  }

  group('a paid target on a free install', () {
    for (final String target in <String>[
      'visionos',
      'horizon',
      'chrome-extension',
      'firefox-extension',
      'vscode',
      'linux-cli',
      'macos-tui',
      'fuchsia',
    ]) {
      test('$target is refused with how to get it, before any work', () async {
        await run(<String>[target]);
        expect(exitCode, 69);
        final String said = output.join('\n');
        expect(said, contains(target));
        expect(said, contains('paid target'));
        expect(said, contains('dartvel build $target --cloud'));
        expect(said, contains('dartvel targets add pro'));
        expect(said, contains('0.11.5 and earlier'));
        // Nothing generated, nothing preflighted.
        expect(invocations, isEmpty);
      });
    }

    test('is still a name the build accepts, so the refusal is reached', () {
      expect(
          resolveRequestedPlatform(
              positional: <String>['visionos'],
              optionValue: 'all',
              optionWasParsed: false),
          'visionos');
      expect(buildTargetArguments(), containsAll(dvPaidTargets.keys));
    });

    test('is not part of a free `all`', () {
      for (final String target in dvPaidTargets.keys) {
        expect(allBuildPlatforms, isNot(contains(target)));
      }
    });

    test('builds on Dartvel Cloud, which carries the paid targets', () async {
      final _RecordingCloud cloud = _RecordingCloud();
      await run(<String>['horizon', '--cloud'], cloud: cloud);
      expect(cloud.requests.single.target, 'horizon');
      expect(exitCode, 0);
    });

    test('a -tui name reaches the cloud as the -cli target it is', () async {
      final _RecordingCloud cloud = _RecordingCloud();
      await run(<String>['linux-tui', '--cloud'], cloud: cloud);
      expect(cloud.requests.single.target, 'linux-cli');
    });

    test('an unknown name is still an unknown name', () {
      expect(
          () => resolveRequestedPlatform(
              positional: <String>['playstation'],
              optionValue: 'all',
              optionWasParsed: false),
          throwsFormatException);
    });
  });

  group('a registered target', () {
    test('is built after generation, with the options it was given', () async {
      final _FakeTarget target = _FakeTarget('hologram');
      DVBuildTargets.register(target);
      await run(<String>['hologram', '--profile', 'profile', '--build-number', '7']);
      expect(exitCode, 0);
      expect(invocations, <String>[
        'preflight hologram',
        'dart run dartvel_cli:dartvel routes --render gui',
      ]);
      final DVBuildTargetContext context = target.contexts.single;
      expect(context.projectRoot, root.path);
      expect(context.options.buildMode, '--profile');
      expect(context.options.buildNumber, '7');
      expect(output.last, contains('Build complete'));
    });

    test('decides the rendering backends generation is told about', () async {
      DVBuildTargets.register(_FakeTarget('hologram-term'));
      await run(<String>['hologram-term']);
      expect(invocations,
          contains('dart run dartvel_cli:dartvel routes --render terminal'));
    });

    test('a failed target fails the build', () async {
      DVBuildTargets.register(
          _FakeTarget('hologram', result: DVBuildTargetResult.failed));
      await run(<String>['hologram']);
      expect(exitCode, 1);
    });

    test('joins `all` when its package is installed', () async {
      DVBuildTargets.register(_FakeTarget('hologram'));
      await run(<String>['all'], preflight: false);
      expect(invocations, contains('preflight hologram'));
    });

    test('cannot take a free target\'s name', () {
      expect(() => DVBuildTargets.register(_FakeTarget('android')),
          throwsArgumentError);
      expect(() => DVBuildTargets.register(_FakeTarget('web-server')),
          throwsArgumentError);
    });

    test('a variant adds its Flutter arguments and is told how the build ended',
        () async {
      Directory('${root.path}/web').createSync();
      File('${root.path}/web/index.html').writeAsStringSync(
          '<!DOCTYPE html><html><head><meta name="viewport" '
          'content="width=device-width, initial-scale=1"></head><body></body></html>');
      final _VariantTarget target = _VariantTarget();
      DVBuildTargets.register(target);
      final List<String> started = <String>[];
      await run(<String>['web-variant', '--no-prerender'],
          processStart: (String executable, List<String> arguments,
              {String? workingDirectory,
              Map<String, String>? environment,
              bool runInShell = false}) async {
        started.add('$executable ${arguments.join(' ')}');
        return _ExitedProcess(1);
      });
      expect(started.single, startsWith('flutter build web'));
      expect(started.single,
          endsWith('--dart-define=DARTVEL_PLATFORM=web-variant'));
      expect(target.events, <String>['prepare', 'finish built=false']);
      expect(output.join('\n'), contains('web-variant build failed'));
      expect(exitCode, 1);
    });
  });

  group('target packages', () {
    test('are found through the project\'s package config', () {
      final Directory package =
          Directory('${root.path}/vendor/dartvel_targets_pro')..createSync(recursive: true);
      File('${package.path}/$dvTargetManifestFile').writeAsStringSync(
          'executable: dartvel_targets\ntargets: [visionos, horizon]\n');
      Directory('${root.path}/.dart_tool').createSync();
      File('${root.path}/.dart_tool/package_config.json').writeAsStringSync(jsonEncode(
        <String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            <String, Object?>{'name': 'shop', 'rootUri': '../', 'packageUri': 'lib/'},
            <String, Object?>{
              'name': 'dartvel_targets_pro',
              'rootUri': '../vendor/dartvel_targets_pro',
              'packageUri': 'lib/',
            },
          ],
        },
      ));
      final DVTargetPackage? found = dvTargetPackageFor(root.path, 'horizon');
      expect(found?.name, 'dartvel_targets_pro');
      expect(found?.executable, 'dartvel_targets');
      expect(dvTargetPackageFor(root.path, 'vscode'), isNull);
    });

    test('a project that has not run pub get has none, and builds free targets',
        () {
      expect(dvTargetPackages(root.path), isEmpty);
    });

    test('a broken manifest is ignored rather than stopping the build', () {
      Directory('${root.path}/.dart_tool').createSync();
      File('${root.path}/.dart_tool/package_config.json')
          .writeAsStringSync('{not json');
      expect(dvTargetPackages(root.path), isEmpty);
    });

    test('a delegated run is recognised, so delegation cannot loop', () {
      expect(dvIsDelegatedRun(<String, String>{dvTargetsDelegatedVariable: '1'}),
          isTrue);
      expect(dvIsDelegatedRun(const <String, String>{}), isFalse);
    });
  });

  group('dartvel targets add pro', () {
    test('adds the private package as a dev dependency from git', () async {
      File('${root.path}/pubspec.yaml').writeAsStringSync(
          'name: shop\ndependencies:\n  flutter:\n    sdk: flutter\n');
      final List<String> ran = <String>[];
      await IOOverrides.runZoned(
        () => (CommandRunner<void>('dartvel', 'test')
              ..addCommand(TargetsCommand(
                root: root.path,
                processRun: (String executable, List<String> arguments,
                    {String? workingDirectory}) async {
                  ran.add('$executable ${arguments.join(' ')}');
                  return ProcessResult(0, 0, '', '');
                },
              )))
            .run(<String>['targets', 'add', 'pro']),
        stdout: () => _BufferStdout(StringBuffer()),
      );
      expect(ran.single, startsWith('flutter pub add dev:dartvel_targets_pro:'));
      expect(ran.single, contains(dvTargetsProGitUrl));
      expect(ran.single, contains(dvTargetsProGitPath));
      expect(exitCode, 0);
    });

    test('refuses anything but pro', () async {
      await IOOverrides.runZoned(
        () => (CommandRunner<void>('dartvel', 'test')
              ..addCommand(TargetsCommand(root: root.path)))
            .run(<String>['targets', 'add', 'enterprise']),
        stdout: () => _BufferStdout(StringBuffer()),
      );
      expect(exitCode, 64);
    });
  });

  test('doctor answers a paid target with how to get it', () async {
    final StringBuffer printed = StringBuffer();
    await IOOverrides.runZoned(
      () => (CommandRunner<void>('dartvel', 'test')
            ..addCommand(DoctorCommand(root: root.path)))
          .run(<String>['doctor', '--target', 'visionos']),
      stdout: () => _BufferStdout(printed),
    );
    expect(printed.toString(), contains('paid target'));
  });
}

/// stdout, into a buffer.
class _BufferStdout implements Stdout {
  _BufferStdout(this._buffer);
  final StringBuffer _buffer;

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
  @override
  void write(Object? object) => _buffer.write(object);
  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data, allowMalformed: true));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
