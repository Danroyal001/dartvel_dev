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
}
