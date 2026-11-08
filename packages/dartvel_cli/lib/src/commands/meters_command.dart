import 'dart:io';

import 'package:args/command_runner.dart';

import '../generators/meter_generator.dart';

/// `dartvel meters list`, as the command prints it.
///
/// Read from the declarations, so it answers in a checkout with nothing
/// running. Separated from the command so it can be tested without a
/// CommandRunner or captured stdout.
Future<String> dvMetersList({required String root}) async {
  final List<DiscoveredMeter> meters = await MeterGenerator.discover(root: root);
  if (meters.isEmpty) {
    return 'No meters are declared. Declare them as `static const name = '
        'DVMeter.counter;` fields of a private class, each marked '
        "@DVMeter(unit: '...'); `dartvel routes` generates `Meters` from them.";
  }
  final List<List<String>> rows = <List<String>>[
    <String>['METER', 'KIND', 'UNIT', 'LIMIT', 'AT LIMIT', 'DECLARED IN'],
    for (final DiscoveredMeter meter in meters)
      <String>[
        meter.name,
        meter.kind == 'gauge' ? 'gauge (${meter.gaugeBilling})' : meter.kind,
        meter.unit,
        meter.limit,
        meter.atLimit,
        meter.file,
      ],
  ];
  return '${_table(rows)}\n\n${meters.length} '
      'meter${meters.length == 1 ? '' : 's'} declared.';
}

String _table(List<List<String>> rows) {
  final List<int> widths = List<int>.filled(rows.first.length, 0);
  for (final List<String> row in rows) {
    for (int i = 0; i < row.length; i++) {
      if (row[i].length > widths[i]) widths[i] = row[i].length;
    }
  }
  return <String>[
    for (final List<String> row in rows)
      <String>[
        for (int i = 0; i < row.length; i++) row[i].padRight(widths[i]),
      ].join('  ').trimRight(),
  ].join('\n');
}

/// `dartvel meters`: the declared usage meters.
///
/// `usage` and `reconcile` read a deployment's records and its billing
/// provider, which needs the deployment's database and credentials and is
/// not here yet; `list` reads only the project.
class MetersCommand extends Command<void> {
  MetersCommand() {
    addSubcommand(_MetersListCommand());
  }

  @override
  final String name = 'meters';

  @override
  String get description => 'List the declared usage meters.';
}

class _MetersListCommand extends Command<void> {
  @override
  final String name = 'list';

  @override
  String get description =>
      'Every declared meter, with its kind, unit, limit and behaviour at it.';

  @override
  Future<void> run() async {
    stdout.writeln(await dvMetersList(root: Directory.current.path));
  }
}
