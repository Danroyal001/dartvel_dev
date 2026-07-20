import 'dart:async';
import 'dart:io';

import 'shell.dart';

Future<DVShellResult> runShellCommand(
  String command, {
  Map<String, String> environment = const <String, String>{},
  String? workingDirectory,
}) async {
  final invocation = DVShellInvocation.parse(command);
  final process = await Process.start(
    invocation.executable,
    invocation.arguments,
    workingDirectory: workingDirectory,
    environment: environment.isEmpty ? null : environment,
    includeParentEnvironment: true,
    runInShell: false,
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final stdoutSub = process.stdout.transform(systemEncoding.decoder).listen(
        stdoutBuffer.write,
      );
  final stderrSub = process.stderr.transform(systemEncoding.decoder).listen(
        stderrBuffer.write,
      );
  final exitCode = await process.exitCode;
  await Future.wait(<Future<void>>[stdoutSub.cancel(), stderrSub.cancel()]);
  return DVShellResult(
    exitCode: exitCode,
    stdoutText: stdoutBuffer.toString(),
    stderrText: stderrBuffer.toString(),
  );
}

class DVShellInvocation {
  final String executable;
  final List<String> arguments;

  const DVShellInvocation({
    required this.executable,
    required this.arguments,
  });

  static DVShellInvocation parse(String command) {
    final tokens = _tokenize(command);
    if (tokens.isEmpty) {
      throw const FormatException('Command is empty.');
    }
    return DVShellInvocation(
      executable: tokens.first,
      arguments: tokens.skip(1).toList(growable: false),
    );
  }

  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final current = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var escaping = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (escaping) {
        current.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\' && !inSingle) {
        escaping = true;
        continue;
      }
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
        continue;
      }
      if (char == '"' && !inSingle) {
        inDouble = !inDouble;
        continue;
      }
      if (!inSingle && !inDouble && char.trim().isEmpty) {
        if (current.isNotEmpty) {
          tokens.add(_expandEnvironment(current.toString()));
          current.clear();
        }
        continue;
      }
      current.write(char);
    }
    if (escaping) current.write(r'\');
    if (inSingle || inDouble) {
      throw const FormatException('Unterminated quoted string.');
    }
    if (current.isNotEmpty) {
      tokens.add(_expandEnvironment(current.toString()));
    }
    return tokens;
  }

  static String _expandEnvironment(String token) {
    final buffer = StringBuffer();
    for (var i = 0; i < token.length; i++) {
      final char = token[i];
      if (char != r'$') {
        buffer.write(char);
        continue;
      }
      if (i + 1 < token.length && token[i + 1] == '{') {
        final end = token.indexOf('}', i + 2);
        if (end == -1) {
          buffer.write(char);
          continue;
        }
        final name = token.substring(i + 2, end);
        buffer.write(Platform.environment[name] ?? '');
        i = end;
        continue;
      }
      final name = StringBuffer();
      var j = i + 1;
      while (j < token.length) {
        final code = token.codeUnitAt(j);
        final isName = (code >= 65 && code <= 90) ||
            (code >= 97 && code <= 122) ||
            (code >= 48 && code <= 57) ||
            code == 95;
        if (!isName) break;
        name.write(token[j]);
        j++;
      }
      if (name.isEmpty) {
        buffer.write(char);
      } else {
        buffer.write(Platform.environment[name.toString()] ?? '');
        i = j - 1;
      }
    }
    return buffer.toString();
  }
}
