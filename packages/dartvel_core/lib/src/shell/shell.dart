import 'shell_unsupported.dart' if (dart.library.io) 'shell_io.dart'
    as shell_impl;

class DVShellResult {
  final int exitCode;
  final String stdoutText;
  final String stderrText;

  const DVShellResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  bool get succeeded => exitCode == 0;
}

class DVShellCommand {
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;

  const DVShellCommand(
    this.executable, {
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.workingDirectory,
  });

  DVShellCommand arg(String value) {
    return DVShellCommand(
      executable,
      arguments: <String>[...arguments, value],
      environment: environment,
      workingDirectory: workingDirectory,
    );
  }

  DVShellCommand args(Iterable<String> values) {
    return DVShellCommand(
      executable,
      arguments: <String>[...arguments, ...values],
      environment: environment,
      workingDirectory: workingDirectory,
    );
  }

  DVShellCommand env(String key, String value) {
    return DVShellCommand(
      executable,
      arguments: arguments,
      environment: <String, String>{...environment, key: value},
      workingDirectory: workingDirectory,
    );
  }

  DVShellCommand envAll(Map<String, String> values) {
    return DVShellCommand(
      executable,
      arguments: arguments,
      environment: <String, String>{...environment, ...values},
      workingDirectory: workingDirectory,
    );
  }

  DVShellCommand cwd(String path) {
    return DVShellCommand(
      executable,
      arguments: arguments,
      environment: environment,
      workingDirectory: path,
    );
  }
}

extension DVShellResultFuture on Future<DVShellResult> {
  Future<String> text() async => (await this).stdoutText;

  Future<String> stderr() async => (await this).stderrText;

  Future<int> code() async => (await this).exitCode;
}

class DVShell {
  const DVShell();

  Future<DVShellResult> call(
    String command, {
    Map<String, String> environment = const <String, String>{},
    String? workingDirectory,
  }) {
    return shell_impl.runShellCommand(
      command,
      environment: environment,
      workingDirectory: workingDirectory,
    );
  }

  Future<DVShellResult> run(
    String command, {
    Map<String, String> environment = const <String, String>{},
    String? workingDirectory,
  }) {
    return call(
      command,
      environment: environment,
      workingDirectory: workingDirectory,
    );
  }

  Future<DVShellResult> runCommand(DVShellCommand command) {
    return shell_impl.runShellCommandParts(
      command.executable,
      command.arguments,
      environment: command.environment,
      workingDirectory: command.workingDirectory,
    );
  }
}
