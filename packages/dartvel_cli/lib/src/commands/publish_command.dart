/// `dartvel publish <store>`: deprecated, and gone in the next release.
///
/// Store submission is `dartvel deploy --store <store>` now. Deploy already
/// shipped a site and a server; a second verb for shipping an application
/// was a second place to look for the same thing. This keeps the old
/// spelling working for one release and prints the new one every time, so
/// a script that still says publish is told what to change before it breaks.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import '../cloud/cloud_build.dart';
import '../publish/store_deploy.dart';
import '../utils/logger.dart';

export '../publish/store_deploy.dart' show PublishProcessRun;

class PublishCommand extends Command<void> {
  /// [root] is the project; null reads the working directory when the command
  /// runs. A test passes its own, because that directory is one value shared
  /// by every suite in the process.
  PublishCommand({
    PublishProcessRun? processRun,
    String? root,
    DVCloudBuilder? cloud,
  }) : _deploy = DVStoreDeploy(
         processRun: processRun,
         root: root,
         cloud: cloud,
       ) {
    argParser
      ..addFlag('dry-run', defaultsTo: false, negatable: false)
      ..addOption('artifact')
      ..addFlag('cloud', defaultsTo: false, negatable: false)
      ..addOption('cloud-token');
  }

  final DVStoreDeploy _deploy;

  @override
  final String name = 'publish';

  @override
  String get description => 'Deprecated: use dartvel deploy --store <store>.';

  @override
  String get invocation => 'dartvel publish <store>';

  /// Hidden, so `dartvel --help` and the reference built from it show one way
  /// to deploy to a store.
  @override
  bool get hidden => true;

  @override
  Future<void> run() async {
    final List<String> rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      Logger.log(
        '⚠️  dartvel publish is deprecated: use '
        'dartvel deploy --store <${dvDeployStores.keys.join('|')}>.',
      );
      exitCode = 64; // EX_USAGE
      return;
    }

    final String given = rest.first;
    // publish's firebase was App Distribution; deploy spells it out.
    final String store = dvDeployStoreName(given) ?? given;
    Logger.log(
      '⚠️  dartvel publish is deprecated and goes in the next '
      'release. Use: ${_deployForm(store, given)}',
    );

    exitCode = await _deploy.run(
      store: store,
      dryRun: argResults?['dry-run'] == true,
      artifact: argResults?['artifact'] as String?,
      cloud: argResults?['cloud'] == true,
      cloudToken: argResults?['cloud-token'] as String?,
    );
  }

  /// The deploy command this invocation is, with a token given on the
  /// command line left out of what is printed into a log.
  String _deployForm(String store, String given) {
    final List<String> arguments = List<String>.of(
      argResults?.arguments ?? const <String>[],
    );
    arguments.remove(given);
    final List<String> shown = <String>[];
    for (int i = 0; i < arguments.length; i++) {
      final String argument = arguments[i];
      if (argument == '--cloud-token') {
        shown.add('--cloud-token <token>');
        i++;
      } else if (argument.startsWith('--cloud-token=')) {
        shown.add('--cloud-token <token>');
      } else {
        shown.add(argument);
      }
    }
    return <String>['dartvel deploy --store', store, ...shown].join(' ');
  }
}
