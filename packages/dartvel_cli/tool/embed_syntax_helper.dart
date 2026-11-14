// Puts the Rust syntax helper inside the CLI, before a release binary is
// compiled.
//
//   cd packages/dartvel_cli
//   dart run tool/embed_syntax_helper.dart            # cargo build, then embed
//   dart build cli --target bin/dartvel.dart
//
// The CLI is shipped as one file (npm, the GitHub release, Homebrew), and
// `dart build cli` has no way to carry a second program. So the helper is
// written into a Dart source file as text, compiled into the executable,
// and written to `~/.dartvel/native/` the first time it is needed
// (`dvInstallSyntaxHelper`). A CLI built without this step carries none and
// parses in Dart.
//
// Options:
//   --rust-target <triple>   build for another architecture, as
//                            `dart build cli --target-arch` does
//   --helper <file>          embed this program instead of building one
//   --clear                  put the repository's empty file back
//
// The output replaces a tracked file. Never commit it: syntax_check_test
// fails on a repository that carries a helper.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const String _carriedFile = 'lib/src/analysis/syntax_helper_carried.g.dart';

/// The source of the carried-helper file: [program] gzipped and
/// base64-encoded, or the empty file of the repository when it is null.
String carriedSource(List<int>? program) {
  final StringBuffer source = StringBuffer('''
// The Rust syntax helper this CLI carries, written by
// `dart tool/embed_syntax_helper.dart` when a release binary is built.
//
// In the repository, and so in the package on pub.dev, it carries none: a
// CLI run from source parses in Dart. Never commit the output of the tool.

/// The helper program for the platform this CLI was built for, gzipped and
/// base64-encoded, or null when this CLI carries none.
''');
  if (program == null) {
    source.writeln('const String? dvCarriedSyntaxHelper = null;');
  } else {
    final String encoded = base64.encode(gzip.encode(program));
    source.writeln('const String? dvCarriedSyntaxHelper =');
    for (int start = 0; start < encoded.length; start += 100) {
      final int end = start + 100 < encoded.length ? start + 100 : encoded.length;
      source.writeln("    '${encoded.substring(start, end)}'${end == encoded.length ? ';' : ''}");
    }
  }
  source
    ..writeln()
    ..writeln('/// The SHA-256 of the helper program, in hexadecimal.')
    ..writeln("const String dvCarriedSyntaxHelperSha256 = '${program == null ? '' : sha256.convert(program)}';");
  return source.toString();
}

Never _fail(String message) {
  stderr.writeln('embed_syntax_helper: $message');
  exit(1);
}

String? _option(List<String> arguments, String name) {
  final int at = arguments.indexOf(name);
  if (at < 0) return null;
  if (at + 1 >= arguments.length) _fail('$name needs a value');
  return arguments[at + 1];
}

Future<void> main(List<String> arguments) async {
  final File carried = File(_carriedFile);
  if (!carried.existsSync()) _fail('run this from packages/dartvel_cli');

  if (arguments.contains('--clear')) {
    carried.writeAsStringSync(carriedSource(null));
    stdout.writeln('embed_syntax_helper: this CLI carries no helper.');
    return;
  }

  final String? rustTarget = _option(arguments, '--rust-target');
  String? helperPath = _option(arguments, '--helper');
  if (helperPath == null) {
    final String workspace = p.normalize(p.join(Directory.current.path, '..', '..', 'rust'));
    final Process cargo = await Process.start(
      'cargo',
      <String>[
        'build',
        '--release',
        '--locked',
        '-p',
        'dartvel_syntax',
        if (rustTarget != null) ...<String>['--target', rustTarget],
      ],
      workingDirectory: workspace,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await cargo.exitCode != 0) _fail('cargo build failed');
    helperPath = p.joinAll(<String>[
      workspace,
      'target',
      if (rustTarget != null) rustTarget,
      'release',
      (rustTarget ?? Platform.operatingSystem).contains('windows') ? 'dartvel_syntax.exe' : 'dartvel_syntax',
    ]);
  }

  final File helper = File(helperPath);
  if (!helper.existsSync()) _fail('no helper at $helperPath');
  final List<int> program = helper.readAsBytesSync();
  if (program.isEmpty) _fail('$helperPath is empty');

  // A helper for this machine must answer before it is shipped. One built
  // for another architecture cannot be run here.
  if (rustTarget == null) {
    final ProcessResult greeting = Process.runSync(helperPath, const <String>['--version']);
    if (greeting.exitCode != 0 || '${greeting.stdout}'.trim() != 'dartvel_syntax\t1') {
      _fail('$helperPath did not greet as protocol 1: ${greeting.stdout}${greeting.stderr}');
    }
  }

  final String source = carriedSource(program);
  carried.writeAsStringSync(source);
  stdout.writeln('embed_syntax_helper: carrying $helperPath '
      '(${program.length} bytes, ${source.length} in the source, sha256 ${sha256.convert(program)}).');
}
