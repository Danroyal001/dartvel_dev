import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

class ShCommand extends Command<void> {
  @override
  final String name = 'sh';

  @override
  String get description =>
      'Run a cross-platform command with Dartvel escaping, env, and glob handling.';

  ShCommand() {
    argParser
      ..addFlag('print',
          abbr: 'p',
          defaultsTo: false,
          help: 'Print the resolved executable and arguments before running.')
      ..addFlag('quiet',
          abbr: 'q',
          defaultsTo: false,
          help: 'Do not stream child process stdout/stderr.')
      ..addMultiOption('env',
          help: 'Environment override in KEY=value form. Can be repeated.');
  }

  @override
  Future<void> run() async {
    final command = argResults?.rest.join(' ').trim() ?? '';
    if (command.isEmpty) {
      throw UsageException('Provide a command to run.', usage);
    }
    final result = await DartvelShell.run(
      command,
      environment: _parseEnv(argResults?['env'] as List<String>? ?? const []),
      printCommand: argResults?['print'] == true,
      streamOutput: argResults?['quiet'] != true,
    );
    if (result.exitCode != 0) {
      exitCode = result.exitCode;
    }
  }
}

class TaskCommand extends Command<void> {
  @override
  final String name = 'task';

  @override
  String get description => 'Run a task from pubspec.yaml dartvel.tasks.';

  TaskCommand() {
    argParser
      ..addFlag('list',
          abbr: 'l', defaultsTo: false, help: 'List available Dartvel tasks.')
      ..addFlag('print',
          abbr: 'p',
          defaultsTo: false,
          help: 'Print the resolved executable and arguments before running.')
      ..addFlag('quiet',
          abbr: 'q',
          defaultsTo: false,
          help: 'Do not stream child process stdout/stderr.');
  }

  @override
  Future<void> run() async {
    final tasks = DartvelTaskFile.load(Directory.current);
    if (argResults?['list'] == true) {
      for (final task in tasks.names) {
        stdout.writeln(task);
      }
      return;
    }
    final taskName =
        argResults?.rest.isEmpty == true ? '' : argResults!.rest.first.trim();
    if (taskName.isEmpty) {
      throw UsageException('Provide a task name, or pass --list.', usage);
    }
    final command = tasks.commandFor(taskName);
    if (command == null) {
      throw UsageException(
          'Unknown task "$taskName". Available tasks: ${tasks.names.join(', ')}',
          usage);
    }
    final forwardedArgs = argResults!.rest.skip(1).toList(growable: false);
    final result = await DartvelShell.run(
      _appendArgs(command, forwardedArgs),
      printCommand: argResults?['print'] == true,
      streamOutput: argResults?['quiet'] != true,
    );
    if (result.exitCode != 0) {
      exitCode = result.exitCode;
    }
  }
}

class DartvelShellResult {
  final int exitCode;
  final String stdoutText;
  final String stderrText;

  const DartvelShellResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  bool get succeeded => exitCode == 0;
}

class DartvelShell {
  const DartvelShell._();

  static Future<DartvelShellResult> run(
    String command, {
    Map<String, String> environment = const <String, String>{},
    bool printCommand = false,
    bool streamOutput = true,
    Directory? workingDirectory,
  }) async {
    final invocation =
        await DartvelShellInvocation.parse(command, workingDirectory);
    if (printCommand) {
      stdout.writeln(invocation.printable);
    }
    final process = await Process.start(
      invocation.executable,
      invocation.arguments,
      workingDirectory: workingDirectory?.path,
      environment: environment.isEmpty ? null : environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    final out = StringBuffer();
    final err = StringBuffer();
    final outSub = process.stdout.transform(systemEncoding.decoder).listen(
      (chunk) {
        out.write(chunk);
        if (streamOutput) stdout.write(chunk);
      },
    );
    final errSub = process.stderr.transform(systemEncoding.decoder).listen(
      (chunk) {
        err.write(chunk);
        if (streamOutput) stderr.write(chunk);
      },
    );
    final code = await process.exitCode;
    await Future.wait(<Future<void>>[outSub.cancel(), errSub.cancel()]);
    return DartvelShellResult(
      exitCode: code,
      stdoutText: out.toString(),
      stderrText: err.toString(),
    );
  }
}

class DartvelShellInvocation {
  final String executable;
  final List<String> arguments;

  const DartvelShellInvocation({
    required this.executable,
    required this.arguments,
  });

  String get printable {
    final parts = <String>[executable, ...arguments];
    return parts.map(_quoteForDisplay).join(' ');
  }

  static Future<DartvelShellInvocation> parse(
    String command, [
    Directory? workingDirectory,
  ]) async {
    final tokens = _tokenize(command);
    if (tokens.isEmpty) {
      throw const FormatException('Command is empty.');
    }
    final expanded = <String>[];
    for (final token in tokens) {
      expanded.addAll(await _expandToken(token, workingDirectory));
    }
    return DartvelShellInvocation(
      executable: expanded.first,
      arguments: expanded.skip(1).toList(growable: false),
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

  static Future<List<String>> _expandToken(
    String token,
    Directory? workingDirectory,
  ) async {
    if (!_hasGlob(token)) return <String>[token];
    final context = p.Context(
      style: Platform.isWindows ? p.Style.windows : p.Style.posix,
      current: workingDirectory?.path ?? Directory.current.path,
    );
    final matches = await Glob(token, context: context)
        .list(root: workingDirectory?.path ?? Directory.current.path)
        .map((entity) => p.relative(entity.path,
            from: workingDirectory?.path ?? Directory.current.path))
        .toList();
    matches.sort();
    return matches.isEmpty ? <String>[token] : matches;
  }

  static bool _hasGlob(String token) =>
      token.contains('*') || token.contains('?') || token.contains('[');

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

  static String _quoteForDisplay(String value) {
    if (value.isEmpty) return "''";
    if (!value.contains(RegExp(r'\s'))) return value;
    return "'${value.replaceAll("'", r"'\''")}'";
  }
}

class DartvelTaskFile {
  final Map<String, String> _tasks;

  const DartvelTaskFile(this._tasks);

  List<String> get names {
    final names = _tasks.keys.toList(growable: false);
    names.sort();
    return names;
  }

  String? commandFor(String name) => _tasks[name];

  static DartvelTaskFile load(Directory root) {
    final pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return const DartvelTaskFile(<String, String>{});
    final parsed = loadYaml(pubspec.readAsStringSync());
    if (parsed is! YamlMap) return const DartvelTaskFile(<String, String>{});
    final dartvel = parsed['dartvel'];
    if (dartvel is! YamlMap) return const DartvelTaskFile(<String, String>{});
    final rawTasks = dartvel['tasks'];
    if (rawTasks is! YamlMap) return const DartvelTaskFile(<String, String>{});
    final tasks = <String, String>{};
    for (final entry in rawTasks.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String && key.trim().isNotEmpty) {
        tasks[key.trim()] = value.trim();
      }
    }
    return DartvelTaskFile(Map<String, String>.unmodifiable(tasks));
  }
}

Map<String, String> _parseEnv(List<String> values) {
  final env = <String, String>{};
  for (final value in values) {
    final splitAt = value.indexOf('=');
    if (splitAt <= 0) {
      throw FormatException('Invalid env value "$value"; expected KEY=value.');
    }
    env[value.substring(0, splitAt)] = value.substring(splitAt + 1);
  }
  return env;
}

String _appendArgs(String command, List<String> args) {
  if (args.isEmpty) return command;
  return '$command ${args.map(DartvelShellInvocation._quoteForDisplay).join(' ')}';
}
