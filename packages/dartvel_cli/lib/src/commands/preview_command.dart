import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../preview/preview_cli.dart';
import 'deploy_command.dart';
import 'dev_command.dart';

/// One-release compatibility shim for `dartvel preview`.
class PreviewCommand extends Command<void> {
  PreviewCommand({
    this.root,
    this.previewHost,
    this.git,
    this.clock,
    void Function(String line)? out,
    this.environment,
  }) : out = out ?? print;

  final String? root;
  final DVPreviewHostResolver? previewHost;
  final DVPreviewGit? git;
  final DateTime Function()? clock;
  final void Function(String line) out;
  final Map<String, String>? environment;

  @override
  String get name => 'preview';
  @override
  String get description => 'Deprecated compatibility command.';
  @override
  bool get hidden => true;
  @override
  final ArgParser argParser = ArgParser.allowAnything();

  @override
  Future<void> run() async {
    final rest = argResults?.rest ?? const <String>[];
    final lifecycle = rest.isNotEmpty && dvPreviewVerbs.contains(rest.first);
    final forwarded = lifecycle
        ? <String>[
            'deploy',
            '--preview',
            if (rest.first != 'create') '--${rest.first}',
            ...rest.skip(1),
          ]
        : <String>['dev', '--release', ...rest];
    final replacement = lifecycle
        ? 'dartvel deploy --preview${rest.first == 'create' ? '' : ' --${rest.first}'}'
        : 'dartvel dev --release';
    out(
      'Deprecated: dartvel preview is available for one release; use $replacement.',
    );
    final runner = CommandRunner<void>('dartvel', 'Dartvel')
      ..addCommand(DevCommand(root: root))
      ..addCommand(
        DeployCommand(
          root: root,
          previewHost: previewHost,
          git: git,
          clock: clock,
          out: out,
          environment: environment ?? Platform.environment,
        ),
      );
    await runner.run(forwarded);
  }
}
