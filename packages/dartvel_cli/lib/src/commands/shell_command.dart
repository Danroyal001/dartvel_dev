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
    final plan = await DartvelShellPlan.parse(command, workingDirectory);
    if (printCommand) {
      stdout.writeln(plan.printable);
    }
    var input = '';
    var stderrText = '';
    var exitCode = 0;
    for (final invocation in plan.invocations) {
      final result = await _runInvocation(
        invocation,
        environment: environment,
        streamOutput: streamOutput && invocation == plan.invocations.last,
        workingDirectory: workingDirectory,
        stdinText: input,
      );
      input = result.stdoutText;
      stderrText = '$stderrText${result.stderrText}';
      exitCode = result.exitCode;
      if (exitCode != 0) break;
    }
    if (plan.stdoutPath != null) {
      _redirectFile(plan.stdoutPath!, workingDirectory).writeAsStringSync(
        input,
        mode: plan.appendStdout ? FileMode.append : FileMode.write,
      );
    }
    if (plan.stderrPath != null) {
      _redirectFile(plan.stderrPath!, workingDirectory).writeAsStringSync(
        stderrText,
        mode: plan.appendStderr ? FileMode.append : FileMode.write,
      );
    }
    return DartvelShellResult(
      exitCode: exitCode,
      stdoutText: plan.stdoutPath == null ? input : '',
      stderrText: plan.stderrPath == null ? stderrText : '',
    );
  }

  static Future<DartvelShellResult> _runInvocation(
    DartvelShellInvocation invocation, {
    required Map<String, String> environment,
    required bool streamOutput,
    required Directory? workingDirectory,
    required String stdinText,
  }) async {
    final process = await Process.start(
      invocation.executable,
      invocation.arguments,
      workingDirectory: workingDirectory?.path,
      environment: environment.isEmpty ? null : environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    if (stdinText.isNotEmpty) {
      process.stdin.write(stdinText);
    }
    await process.stdin.close();
    final out = StringBuffer();
    final err = StringBuffer();
    // Drained to completion rather than listened-to and cancelled.
    //
    // process.exitCode completes when the process exits, which can be before
    // its output has been delivered to the listener -- the pipes still hold
    // it. Cancelling the subscriptions at that point discarded whatever had
    // not arrived, so a command that exits immediately, which is most of
    // them, could lose its output entirely.
    //
    // It is not only about what is printed: stdoutText is what a pipeline
    // feeds to its next stage, so `a | b` could hand b an empty stdin and
    // produce nothing at all. And being a race it was intermittent, which
    // reads as a flaky tool rather than as a bug.
    final Future<void> outDone =
        process.stdout.transform(systemEncoding.decoder).forEach((chunk) {
      out.write(chunk);
      if (streamOutput) stdout.write(chunk);
    });
    final Future<void> errDone =
        process.stderr.transform(systemEncoding.decoder).forEach((chunk) {
      err.write(chunk);
      if (streamOutput) stderr.write(chunk);
    });

    final code = await process.exitCode;
    // Both close when the process's pipes close, at or after exit, so this
    // terminates.
    await Future.wait(<Future<void>>[outDone, errDone]);
    return DartvelShellResult(
      exitCode: code,
      stdoutText: out.toString(),
      stderrText: err.toString(),
    );
  }

  static File _redirectFile(String path, Directory? workingDirectory) {
    final file = p.isAbsolute(path)
        ? File(path)
        : File(p.join(workingDirectory?.path ?? Directory.current.path, path));
    file.parent.createSync(recursive: true);
    return file;
  }
}

class DartvelShellPlan {
  final List<DartvelShellInvocation> invocations;
  final String? stdoutPath;
  final String? stderrPath;
  final bool appendStdout;
  final bool appendStderr;

  const DartvelShellPlan({
    required this.invocations,
    required this.stdoutPath,
    required this.stderrPath,
    required this.appendStdout,
    required this.appendStderr,
  });

  String get printable {
    final pipeline =
        invocations.map((invocation) => invocation.printable).join(' | ');
    return <String>[
      pipeline,
      if (stdoutPath != null) '${appendStdout ? '>>' : '>'} $stdoutPath',
      if (stderrPath != null) '${appendStderr ? '2>>' : '2>'} $stderrPath',
    ].join(' ');
  }

  static Future<DartvelShellPlan> parse(
    String command, [
    Directory? workingDirectory,
  ]) async {
    final tokens = DartvelShellInvocation._tokenize(command);
    if (tokens.isEmpty) {
      throw const FormatException('Command is empty.');
    }
    final stages = <List<String>>[<String>[]];
    String? stdoutPath;
    String? stderrPath;
    var appendStdout = false;
    var appendStderr = false;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token == '|') {
        if (stages.last.isEmpty) {
          throw const FormatException('Pipeline stage is empty.');
        }
        stages.add(<String>[]);
        continue;
      }
      if (token == '>' || token == '>>' || token == '2>' || token == '2>>') {
        if (i + 1 >= tokens.length) {
          throw FormatException('Missing path after "$token".');
        }
        final target = tokens[++i];
        if (token == '>' || token == '>>') {
          stdoutPath = target;
          appendStdout = token == '>>';
        } else {
          stderrPath = target;
          appendStderr = token == '2>>';
        }
        continue;
      }
      stages.last.add(token);
    }
    if (stages.last.isEmpty) {
      throw const FormatException('Pipeline stage is empty.');
    }
    final invocations = <DartvelShellInvocation>[];
    for (final stage in stages) {
      final expanded = <String>[];
      for (final token in stage) {
        expanded.addAll(
          await DartvelShellInvocation._expandToken(token, workingDirectory),
        );
      }
      invocations.add(DartvelShellInvocation(
        executable: expanded.first,
        arguments: expanded.skip(1).toList(growable: false),
      ));
    }
    return DartvelShellPlan(
      invocations: invocations,
      stdoutPath: stdoutPath,
      stderrPath: stderrPath,
      appendStdout: appendStdout,
      appendStderr: appendStderr,
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
      if (!inSingle && !inDouble) {
        final operator = _operatorAt(input, i);
        if (operator != null) {
          if (current.isNotEmpty) {
            tokens.add(_expandEnvironment(current.toString()));
            current.clear();
          }
          tokens.add(operator);
          i += operator.length - 1;
          continue;
        }
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

  static String? _operatorAt(String input, int index) {
    if (input.startsWith('2>>', index)) return '2>>';
    if (input.startsWith('2>', index)) return '2>';
    if (input.startsWith('>>', index)) return '>>';
    final char = input[index];
    return char == '|' || char == '>' ? char : null;
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
    final tasks = <String, String>{};
    tasks.addAll(_loadPubspecTasks(root));
    tasks.addAll(_loadShellScriptTasks(root));
    tasks.addAll(_loadDartScriptTasks(root));
    return DartvelTaskFile(Map<String, String>.unmodifiable(tasks));
  }

  static Map<String, String> _loadPubspecTasks(Directory root) {
    final pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return const <String, String>{};
    final parsed = loadYaml(pubspec.readAsStringSync());
    if (parsed is! YamlMap) return const <String, String>{};
    final dartvel = parsed['dartvel'];
    if (dartvel is! YamlMap) return const <String, String>{};
    final rawTasks = dartvel['tasks'];
    if (rawTasks is! YamlMap) return const <String, String>{};
    return _tasksFromEntries(rawTasks.entries.map((entry) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) {
        return MapEntry<String, String>(key, value);
      }
      return const MapEntry<String, String>('', '');
    }));
  }

  static Map<String, String> _loadShellScriptTasks(Directory root) {
    final script = File(p.join(root.path, '.dartvel.sh'));
    if (!script.existsSync()) return const <String, String>{};
    return _tasksFromLines(script.readAsLinesSync());
  }

  static Map<String, String> _loadDartScriptTasks(Directory root) {
    final script = File(p.join(root.path, '.dartvel.dart'));
    if (!script.existsSync()) return const <String, String>{};
    final declared = _tasksFromLines(script.readAsLinesSync());
    if (declared.isNotEmpty) return declared;
    return <String, String>{
      'dartvel': '${Platform.resolvedExecutable} ${script.path}',
    };
  }

  static Map<String, String> _tasksFromLines(List<String> lines) {
    final entries = <MapEntry<String, String>>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final withoutComment =
          trimmed.startsWith('//') ? trimmed.substring(2).trimLeft() : trimmed;
      final declaration = withoutComment.startsWith('task ')
          ? withoutComment.substring(5).trimLeft()
          : withoutComment;
      final spacedSeparator = declaration.indexOf(': ');
      final separator =
          spacedSeparator == -1 ? declaration.indexOf(':') : spacedSeparator;
      if (separator <= 0) continue;
      entries.add(MapEntry<String, String>(
        declaration.substring(0, separator),
        declaration.substring(separator + 1),
      ));
    }
    return _tasksFromEntries(entries);
  }

  static Map<String, String> _tasksFromEntries(
    Iterable<MapEntry<String, String>> entries,
  ) {
    final tasks = <String, String>{};
    for (final entry in entries) {
      final name = entry.key.trim();
      final command = entry.value.trim();
      if (name.isNotEmpty && command.isNotEmpty) tasks[name] = command;
    }
    return tasks;
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
