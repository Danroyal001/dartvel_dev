// `dartvel --version | head -1` closes the pipe after one line. A command-line
// tool reading that as the end of its output stops quietly; the CLI used to
// print an unhandled FileSystemException and a stack trace, and exit 255.
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('output cut short by the reader ends quietly, with no stack trace', () async {
    final String cli = p.absolute('bin', 'dartvel.dart');
    final String packages = p.absolute('.dart_tool', 'package_config.json');
    final ProcessResult run = await Process.run('bash', <String>[
      '-c',
      '"${Platform.resolvedExecutable}" --packages="$packages" "$cli" --version 2>err.txt | head -c 1 >/dev/null; '
          'echo "\${PIPESTATUS[0]}"; cat err.txt; rm -f err.txt',
    ], workingDirectory: Directory.systemTemp.createTempSync('dv_pipe_').path);
    final List<String> lines = '${run.stdout}'.trim().split('\n');
    expect(lines.skip(1).join('\n'), isNot(contains('Unhandled exception')));
    expect(lines.skip(1).join('\n'), isNot(contains('Broken pipe')));
    expect(int.parse(lines.first), anyOf(0, 141), reason: 'quietly: 0, or what a shell reports for SIGPIPE');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
