import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dartvel_core/dartvel.dart'
    show
        DVCompatibilityCheck,
        DVCompatibilityVerdict,
        DVProtocolLock,
        DVProtocolPlan,
        DVProtocolProblem,
        DVProtocolRelease,
        DVProtocolSessionSample,
        DVProtocolVersionPlan,
        DVProtocolWindow;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// `dartvel compatibility-check` -- the build's protocol against the clients
/// an environment serves.
///
/// On its own it checks what the build can: that a protocol is recorded, that
/// the lockfile is the one the build wrote, and that every version inside the
/// window can be served (`DV-PROTO-004`, `DV-PROTO-006`). With `--against` it
/// is the deploy gate as well (`DV-PROTO-005`), which needs the client
/// histogram for that environment.
class CompatibilityCheckCommand extends Command<void> {
  CompatibilityCheckCommand() {
    argParser
      ..addOption(
        'against',
        valueHelp: 'environment',
        help:
            'The environment whose clients the build is checked against, '
            'e.g. production. Needs --histogram.',
      )
      ..addOption(
        'histogram',
        valueHelp: 'file',
        help:
            'JSON sessions per protocol version per day, exported from '
            'monitoring for that environment: '
            '{"samples": [{"protocol": 6, "day": "2026-09-10", '
            '"sessions": 1200}]}.',
      )
      ..addOption(
        'override',
        valueHelp: 'reason',
        help:
            'Let a refused deploy through. The reason is logged with the '
            'histogram it overrode, in .dartvel/compatibility-overrides.jsonl.',
      );
  }

  @override
  final String name = 'compatibility-check';

  @override
  final String description =
      'Check the build\'s protocol against the clients an environment serves.';

  @override
  String get invocation =>
      'dartvel compatibility-check [--against <environment> --histogram '
      '<file>] [--override <reason>]';

  @override
  Future<void> run() async {
    final int code = await dvRunCompatibilityCheck(
      Directory.current.path,
      against: argResults!['against'] as String?,
      histogramPath: argResults!['histogram'] as String?,
      overrideReason: argResults!['override'] as String?,
      now: DateTime.now().toUtc(),
      out: stdout.writeln,
    );
    if (code != 0) exitCode = code;
  }
}

/// Where overrides are appended, one JSON record per line.
const String dvCompatibilityOverrideLog =
    '.dartvel/compatibility-overrides.jsonl';

/// The body of `dartvel compatibility-check`: 0 compatible or overridden, 1
/// refused. Nothing is written except an override's record.
Future<int> dvRunCompatibilityCheck(
  String root, {
  String? against,
  String? histogramPath,
  String? overrideReason,
  required DateTime now,
  required void Function(String) out,
}) async {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    out(
      'No pubspec.yaml here. Run compatibility-check from the root of a '
      'project.',
    );
    return 1;
  }

  final DVProtocolWindow window;
  try {
    final Object? doc = loadYaml(pubspec.readAsStringSync());
    final Object? dartvel = doc is Map ? doc['dartvel'] : null;
    final Object? protocol = dartvel is Map ? dartvel['protocol'] : null;
    if (protocol != null && protocol is! Map) {
      throw const FormatException('dartvel.protocol must be a map');
    }
    window = DVProtocolWindow.fromConfig(protocol as Map<Object?, Object?>?);
  } on FormatException catch (e) {
    out('Refused: ${e.message}.');
    return 1;
  }

  final File lockFile = File(p.join(root, DVProtocolLock.fileName));
  if (!lockFile.existsSync()) {
    out(
      'Refused: there is no ${DVProtocolLock.fileName}, so this project has '
      'no recorded protocol and nothing to hold a client against. That is '
      'not the same as compatible.',
    );
    return 1;
  }
  final DVProtocolLock lock;
  try {
    lock = DVProtocolLock.decode(lockFile.readAsStringSync());
  } on FormatException catch (e) {
    out('Refused: ${DVProtocolLock.fileName} cannot be trusted: ${e.message}.');
    return 1;
  }
  final DVProtocolRelease? current = lock.current;
  if (current == null) {
    out('Refused: ${DVProtocolLock.fileName} records no protocol version.');
    return 1;
  }

  final DVProtocolPlan plan = DVProtocolPlan.build(
    lock: lock,
    window: window,
    now: now,
    // Reported below, once, in this command's output.
    onDiagnostic: (String code, String message) {},
  );
  final List<int> served = plan.versions.keys.toList()..sort();
  out(
    'The build speaks protocol ${current.protocol} (shape ${current.shape}). '
    'Its window serves ${served.join(', ')}:',
  );
  for (final int protocol in served.reversed) {
    final DVProtocolVersionPlan version = plan.versions[protocol]!;
    final String changes = version.changes.isEmpty
        ? 'no changes'
        : '${version.changes.length} '
              '${version.changes.length == 1 ? 'change' : 'changes'}';
    out('  protocol $protocol: ${version.result.name} ($changes)');
  }
  for (final DVProtocolProblem warning in plan.warnings) {
    out('warning ${warning.code}: ${warning.message}');
  }
  for (final DVProtocolProblem error in plan.errors) {
    out('error ${error.code}: ${error.message}');
  }
  if (plan.errors.isNotEmpty) {
    out(
      'Refused: ${plan.errors.length} version(s) inside the window cannot '
      'be served as recorded.',
    );
    return 1;
  }

  if (against == null) {
    if (histogramPath != null || overrideReason != null) {
      out(
        'Refused: --histogram and --override belong to --against '
        '<environment>.',
      );
      return 1;
    }
    return 0;
  }

  if (histogramPath == null) {
    out(
      'Refused: no client histogram for $against. The gate compares the '
      'build\'s window with the sessions per protocol version that '
      '$against served over the last seven days. Monitoring does not '
      'record that yet, so export it and pass it with --histogram <file>. '
      'Without one there is no evidence that nobody would be stranded.',
    );
    return 1;
  }

  final String histogramFile = p.isAbsolute(histogramPath)
      ? histogramPath
      : p.join(root, histogramPath);
  final List<DVProtocolSessionSample> samples;
  try {
    samples = dvReadSessionHistogram(File(histogramFile).readAsStringSync());
  } on FileSystemException catch (e) {
    out('Refused: cannot read the histogram $histogramPath: ${e.message}.');
    return 1;
  } on FormatException catch (e) {
    out(
      'Refused: the histogram $histogramPath is not readable: '
      '${e.message}.',
    );
    return 1;
  }

  final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
    candidate: lock,
    window: window,
    samples: samples,
    now: now,
    overrideReason: overrideReason,
    onDiagnostic: (String code, String message) {},
  );

  final int total = verdict.histogram.values.fold(0, (int a, int b) => a + b);
  out(
    'Sessions on $against over the last seven days: '
    '${_describe(verdict.histogram, total)}.',
  );

  if (verdict.refusal == null) {
    out(
      'Compatible: no version outside the window carries more than '
      '${_percent(verdict.threshold)} of sessions.',
    );
    return 0;
  }
  final String refusal = verdict.stranded.isEmpty
      ? verdict.refusal!
      : 'DV-PROTO-005: ${verdict.refusal!}';
  if (!verdict.overridden) {
    out('Refused: $refusal');
    return 1;
  }

  final Map<String, Object?> record = <String, Object?>{
    'at': now.toUtc().toIso8601String(),
    'environment': against,
    ...verdict.toJson(),
  };
  final File log = File(p.join(root, dvCompatibilityOverrideLog));
  log.parent.createSync(recursive: true);
  log.writeAsStringSync(
    '${jsonEncode(record)}\n',
    mode: FileMode.append,
    flush: true,
  );
  out('Overridden: $refusal');
  out('Logged to $dvCompatibilityOverrideLog: ${jsonEncode(record)}');
  return 0;
}

/// Reads a histogram export: `{"samples": [...]}` or the list on its own,
/// each sample `{"protocol": int, "day": "YYYY-MM-DD", "sessions": int}`.
///
/// Refuses anything else rather than skipping it, because a sample dropped
/// for being malformed is a client that silently stopped counting.
List<DVProtocolSessionSample> dvReadSessionHistogram(String source) {
  final Object? root;
  try {
    root = jsonDecode(source);
  } on FormatException catch (e) {
    throw FormatException('not JSON: ${e.message}');
  }
  final Object? list = root is Map ? root['samples'] : root;
  if (list is! List) {
    throw const FormatException(
      'expected {"samples": [...]} or a list of samples',
    );
  }
  final RegExp dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  return <DVProtocolSessionSample>[
    for (final (int index, Object? entry) in list.indexed)
      () {
        if (entry is! Map) {
          throw FormatException('sample $index is not an object');
        }
        final Object? protocol = entry['protocol'];
        final Object? day = entry['day'];
        final Object? sessions = entry['sessions'];
        if (protocol is! int) {
          throw FormatException('sample $index: protocol must be an integer');
        }
        final RegExpMatch? match = day is String
            ? dayPattern.firstMatch(day)
            : null;
        if (match == null) {
          throw FormatException('sample $index: day must be YYYY-MM-DD');
        }
        if (sessions is! int || sessions < 0) {
          throw FormatException(
            'sample $index: sessions must be a non-negative integer',
          );
        }
        return DVProtocolSessionSample(
          protocol: protocol,
          day: DateTime.utc(
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
            int.parse(match.group(3)!),
          ),
          sessions: sessions,
        );
      }(),
  ];
}

String _percent(double share) => '${(share * 100).toStringAsFixed(2)}%';

String _describe(Map<int, int> histogram, int total) {
  if (total == 0) return 'none';
  final List<int> versions = histogram.keys.toList()..sort();
  return versions
      .map(
        (int v) =>
            'protocol $v ${histogram[v]} (${_percent(histogram[v]! / total)})',
      )
      .join(', ');
}
