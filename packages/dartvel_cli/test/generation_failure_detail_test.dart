// What `dartvel build` shows when generating the client fails: the reason,
// not just that it failed. The generator runs in a child process; its output
// was dropped, so "artifact generation failed" was all a developer saw.
import 'dart:io';

import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

void main() {
  test('shows the error the generator gave, without its convention warnings', () {
    final List<String> shown = generationFailureDetail(ProcessResult(
      1,
      255,
      '[dartvel] ⚠ DV-CONV-012 lib/pages/a.dart: something stylistic\n'
          'An error occurred: Bad state: @DVAppRoot requires a private function in lib/boot.dart\n',
      'Running build hooks...',
    ));
    expect(shown, contains('An error occurred: Bad state: @DVAppRoot requires a private function in lib/boot.dart'));
    expect(shown.where((String line) => line.contains('DV-CONV')), isEmpty);
  });

  test('stderr is shown in full', () {
    final List<String> shown =
        generationFailureDetail(ProcessResult(1, 1, '', 'Unhandled exception:\nFileSystemException: x'));
    expect(shown, <String>['Unhandled exception:', 'FileSystemException: x']);
  });

  test('a long log is cut to its end, where the error is', () {
    final String noise = List<String>.generate(200, (int i) => 'line $i').join('\n');
    final List<String> shown = generationFailureDetail(ProcessResult(1, 1, '$noise\nthe error', ''));
    expect(shown.length, lessThanOrEqualTo(40));
    expect(shown.last, 'the error');
  });
}
