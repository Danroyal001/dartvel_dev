import 'dart:async';
import 'dart:io';

import 'shell.dart';

Future<DVShellResult> runShellCommand(
  String command, {
  Map<String, String> environment = const <String, String>{},
  String? workingDirectory,
}) async {
  final invocation = DVShellInvocation.parse(command);
  final arguments = await invocation.expandArguments(
    workingDirectory: workingDirectory,
  );
  return runShellCommandParts(
    invocation.executable,
    arguments,
    environment: environment,
    workingDirectory: workingDirectory,
  );
}

Future<DVShellResult> runShellCommandParts(
  String executable,
  List<String> arguments, {
  Map<String, String> environment = const <String, String>{},
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
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

  Future<List<String>> expandArguments({String? workingDirectory}) async {
    final expanded = <String>[];
    for (final argument in arguments) {
      expanded.addAll(await _expandGlob(argument, workingDirectory));
    }
    return expanded;
  }

  static Future<List<String>> _expandGlob(
    String token,
    String? workingDirectory,
  ) async {
    if (!_hasGlob(token)) return <String>[token];
    final root = Directory(workingDirectory ?? Directory.current.path);
    if (!root.existsSync()) return <String>[token];
    final recursive = token.contains('**');
    final matcher = RegExp('^${_globToRegex(token)}\$');
    final matches = <String>[];
    await for (final entity in root.list(recursive: recursive)) {
      if (entity is! File) continue;
      final relative = _relativePath(entity.path, root.path);
      if (matcher.hasMatch(relative)) matches.add(relative);
    }
    matches.sort();
    return matches.isEmpty ? <String>[token] : matches;
  }

  static bool _hasGlob(String token) =>
      token.contains('*') || token.contains('?') || token.contains('[');

  static String _relativePath(String path, String root) {
    final normalizedRoot = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    final relative = path.startsWith(normalizedRoot)
        ? path.substring(normalizedRoot.length)
        : path;
    return relative.replaceAll(Platform.pathSeparator, '/');
  }

  static String _globToRegex(String pattern) {
    final buffer = StringBuffer();
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          buffer.write('.*');
          i++;
        } else {
          buffer.write('[^/]*');
        }
        continue;
      }
      if (char == '?') {
        buffer.write('[^/]');
        continue;
      }
      if (char == '[') {
        final end = pattern.indexOf(']', i + 1);
        if (end != -1) {
          buffer.write(pattern.substring(i, end + 1));
          i = end;
          continue;
        }
      }
      buffer.write(RegExp.escape(char));
    }
    return buffer.toString();
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
