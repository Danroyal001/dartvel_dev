import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../store/data_safety.dart';

/// Reads `pubspec.yaml` under [root] as plain maps.
Map<Object?, Object?> _readPubspec(String root) {
  final File file = File(p.join(root, 'pubspec.yaml'));
  if (!file.existsSync()) {
    throw UsageException('No pubspec.yaml in $root.', '');
  }
  final Object? doc = loadYaml(file.readAsStringSync());
  return doc is Map ? doc : const <Object?, Object?>{};
}

DVDataSafetyReport _reportFor(String root) {
  try {
    return dvDataSafetyFor(DVDataSafetyInputs.fromPubspec(_readPubspec(root)));
  } on ArgumentError catch (error) {
    throw UsageException('pubspec.yaml: ${error.message}', '');
  }
}

/// Writes `data-safety.csv` and `data-safety-worksheet.md` into [directory]
/// and returns their paths. What `dartvel build android --format aab` runs
/// beside the bundle it makes.
List<String> dvWriteDataSafetyFiles({
  required String root,
  required String directory,
  String? template,
  bool unverifiedIds = false,
}) {
  final DVDataSafetyReport report = _reportFor(root);
  Directory(directory).createSync(recursive: true);
  final File csv = File(p.join(directory, 'data-safety.csv'))
    ..writeAsStringSync(
        report.toCsv(template: template, unverifiedIds: unverifiedIds));
  final File sheet = File(p.join(directory, 'data-safety-worksheet.md'))
    ..writeAsStringSync(
        report.toWorksheet(template: template, unverifiedIds: unverifiedIds));
  return <String>[csv.path, sheet.path];
}

/// `dartvel store ...`: what the app stores ask of a project.
class StoreCommand extends Command<void> {
  StoreCommand({String? root, void Function(String line)? out}) {
    addSubcommand(_DataSafetyCommand(root, out ?? stdout.writeln));
  }

  @override
  final String name = 'store';

  @override
  final String description = 'Answers the app stores ask for, from the project.';
}

class _DataSafetyCommand extends Command<void> {
  _DataSafetyCommand(this._root, this._out) {
    argParser
      ..addOption('format',
          allowed: <String>['csv', 'json', 'worksheet'],
          defaultsTo: 'csv',
          help: 'What to print when --out is not given.')
      ..addOption('out',
          help: 'Write data-safety.csv and data-safety-worksheet.md here.')
      ..addOption('template',
          help: "The CSV exported from Play Console's Data safety page. Its "
              'identifiers are used for every data type it lists.')
      ..addFlag('unverified-ids',
          negatable: false,
          help: 'Also write rows under identifiers Google does not publish '
              '(recalled from the Console template). The Console shows an '
              'error for any it does not know; check the import preview.');
  }

  final String? _root;
  final void Function(String line) _out;

  @override
  final String name = 'data-safety';

  @override
  final String description =
      "Play Console Data safety answers (import CSV) from the project's "
      'declarations. What cannot be derived is listed as TODO, never guessed.';

  @override
  void run() {
    final String root = _root ?? Directory.current.path;
    final String? templatePath = argResults!['template'] as String?;
    String? template;
    if (templatePath != null) {
      final File file = File(templatePath);
      if (!file.existsSync()) {
        throw UsageException('No template at $templatePath.', usage);
      }
      template = file.readAsStringSync();
    }
    final bool unverified = argResults!['unverified-ids'] as bool;
    final String? out = argResults!['out'] as String?;
    if (out != null) {
      for (final String path in dvWriteDataSafetyFiles(
          root: root,
          directory: out,
          template: template,
          unverifiedIds: unverified)) {
        _out('Wrote $path');
      }
      return;
    }
    final DVDataSafetyReport report = _reportFor(root);
    switch (argResults!['format'] as String) {
      case 'json':
        _out(const JsonEncoder.withIndent('  ').convert(report.toJson()));
      case 'worksheet':
        _out(report.toWorksheet(template: template, unverifiedIds: unverified));
      default:
        _out(report.toCsv(template: template, unverifiedIds: unverified).trimRight());
    }
  }
}
