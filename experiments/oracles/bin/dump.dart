import 'dart:io';

import 'package:oracles/oracles.dart';

const _usage = '''
Usage: dart bin/dump.dart <corpus-dir>... --out <dir> --tool format|analyze
                          [--language-version <major.minor>]

Records what the original tool produces for every .dart file under the
corpus directories. <dir> must be empty, absent, or an earlier dump.''';

Future<void> main(List<String> args) async {
  final roots = <String>[];
  String? out;
  String? tool;
  String? languageVersion;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String value() => ++i < args.length ? args[i] : '';
    switch (arg) {
      case '--out':
        out = value();
      case '--tool':
        tool = value();
      case '--language-version':
        languageVersion = value();
      case '-h' || '--help':
        stdout.writeln(_usage);
        return;
      default:
        if (arg.startsWith('-')) return _fail('unknown option $arg');
        roots.add(arg);
    }
  }
  final dumpTool = DumpTool.values.where((t) => t.name == tool).firstOrNull;
  if (dumpTool == null) return _fail('--tool must be format or analyze');
  if (out == null || out.isEmpty) return _fail('--out is required');
  if (roots.isEmpty) return _fail('name at least one corpus directory');
  if (languageVersion != null && dumpTool != DumpTool.format) {
    return _fail('--language-version applies to --tool format only');
  }

  final stopwatch = Stopwatch()..start();
  try {
    final summary = await dump(
      roots: roots,
      outDir: out,
      tool: dumpTool,
      languageVersion: languageVersion,
    );
    stdout.writeln(
      '${dumpTool.name}: ${summary.fileCount} files, '
      '${summary.errorCount} recorded errors, '
      '${stopwatch.elapsed.inMilliseconds} ms\n'
      'overall sha256 ${summary.overallSha256}',
    );
  } on ArgumentError catch (e) {
    return _fail('${e.message}: ${e.invalidValue}');
  } on StateError catch (e) {
    return _fail(e.message);
  }
}

void _fail(String message) {
  stderr
    ..writeln('error: $message')
    ..writeln(_usage);
  exitCode = 64;
}
