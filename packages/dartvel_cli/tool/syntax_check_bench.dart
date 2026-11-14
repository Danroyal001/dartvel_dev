// Times the syntax check with and without the Rust helper.
//
//   dart compile exe tool/syntax_check_bench.dart -o /tmp/syntax_check_bench
//   /tmp/syntax_check_bench ../../rust/target/release/dartvel_syntax <root>...
//
// Compile it: the CLI people run is compiled, and the Dart analyzer under
// `dart run` is several times slower than it is there. Every `.dart` file
// under each root is checked, generated ones included, so the numbers are
// about parsing and not about which files a project has.
import 'dart:io';

import 'package:dartvel_cli/src/analysis/syntax_check.dart';
import 'package:path/path.dart' as p;

const Set<String> _skippedDirectories = <String>{'.dart_tool', '.git', 'build', 'node_modules', 'target'};

void _collect(Directory directory, List<String> files) {
  for (final FileSystemEntity entry in directory.listSync(followLinks: false)) {
    final String name = p.basename(entry.path);
    if (entry is Directory) {
      if (!_skippedDirectories.contains(name)) _collect(entry, files);
    } else if (entry is File && name.endsWith('.dart')) {
      files.add(p.absolute(entry.path));
    }
  }
}

String _milliseconds(int microseconds) => '${(microseconds / 1000).toStringAsFixed(1)} ms';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln('usage: syntax_check_bench <helper> <root>...');
    exit(64);
  }
  final DVSyntaxHelper helper = DVSyntaxHelper(arguments.first);
  const int rounds = 9;
  for (final String root in arguments.skip(1)) {
    final List<String> files = <String>[];
    _collect(Directory(root), files);
    files.sort();
    final int bytes = files.fold(0, (int total, String path) => total + File(path).lengthSync());

    final List<int> dartTimes = <int>[];
    final List<int> helperTimes = <int>[];
    late DVSyntaxReport dartReport;
    late DVSyntaxReport helperReport;
    // Alternating, so that neither engine always runs on a warmer cache.
    for (int round = 0; round < rounds; round++) {
      final Stopwatch dartWatch = Stopwatch()..start();
      dartReport = await dvCheckSyntaxOf('/', files);
      dartTimes.add(dartWatch.elapsedMicroseconds);
      final Stopwatch helperWatch = Stopwatch()..start();
      helperReport = await dvCheckSyntaxOf('/', files, helper: helper);
      helperTimes.add(helperWatch.elapsedMicroseconds);
    }
    dartTimes.sort();
    helperTimes.sort();
    final bool same = dartReport.findings.map((DVSyntaxFinding finding) => '$finding').join('\n') ==
        helperReport.findings.map((DVSyntaxFinding finding) => '$finding').join('\n');
    stdout
      ..writeln('$root: ${files.length} files, $bytes bytes, $rounds rounds')
      ..writeln('  Dart analyzer only:  fastest ${_milliseconds(dartTimes.first)}, '
          'median ${_milliseconds(dartTimes[rounds ~/ 2])}')
      ..writeln('  with the helper:     fastest ${_milliseconds(helperTimes.first)}, '
          'median ${_milliseconds(helperTimes[rounds ~/ 2])} '
          '(${helperReport.cleanByHelper} files answered by the helper, '
          '${helperReport.parsedInDart} parsed in Dart)')
      ..writeln('  findings: ${dartReport.findings.length} without the helper, '
          '${helperReport.findings.length} with it, ${same ? 'identical' : 'DIFFERENT'}');
  }
}
