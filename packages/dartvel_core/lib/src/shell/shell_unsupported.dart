import 'shell.dart';

Future<DVShellResult> runShellCommand(
  String command, {
  Map<String, String> environment = const <String, String>{},
  String? workingDirectory,
}) async {
  return DVShellResult(
    exitCode: 126,
    stdoutText: '',
    stderrText:
        'DV.\$ cannot start local processes on this platform. Command: $command',
  );
}

Future<DVShellResult> runShellCommandParts(
  String executable,
  List<String> arguments, {
  Map<String, String> environment = const <String, String>{},
  String? workingDirectory,
}) async {
  return DVShellResult(
    exitCode: 126,
    stdoutText: '',
    stderrText:
        'DV.\$ cannot start local processes on this platform. Command: $executable ${arguments.join(' ')}',
  );
}
