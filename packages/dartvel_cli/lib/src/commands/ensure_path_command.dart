import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../build/ensure_path.dart';
import '../utils/logger.dart';

/// `dartvel ensure-path` — make the command findable in the next terminal.
///
/// A binary downloaded from a release lands wherever the browser put it. It
/// runs from there, and then a new shell cannot find it, which reads as a
/// broken install rather than an unset variable.
class EnsurePathCommand extends Command<void> {
  @override
  final String name = 'ensure-path';

  @override
  final String description =
      'Add the dartvel command to your PATH, if it is not already.';

  @override
  String get invocation => 'dartvel ensure-path [--dry-run] [--system]';

  EnsurePathCommand() {
    argParser
      ..addFlag('dry-run',
          negatable: false,
          help: 'Print what would change without changing anything.')
      ..addFlag('system',
          negatable: false,
          help: 'Change the PATH for every user rather than just this one. '
              'Needs administrator on Windows and root elsewhere.')
      ..addOption('directory',
          help: 'The directory to add. Defaults to the one this binary is in.');
  }

  @override
  Future<void> run() async {
    final directory = (argResults!['directory'] as String?) ?? _selfDirectory();
    if (directory == null) {
      Logger.error('Could not work out where this binary lives. '
          'Pass --directory to say.');
      exit(1);
    }

    final plan = ensurePathPlan(
      directory: directory,
      currentPath: Platform.environment['PATH'] ?? '',
      platform: _platform(),
      scope: (argResults!['system'] as bool) ? PathScope.system : PathScope.user,
      shell: Platform.environment['SHELL'],
      home: Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'],
    );

    if (plan.alreadyPresent) {
      Logger.log('$directory is already on your PATH. Nothing to do.');
      return;
    }

    // Said before anything is attempted, not after it fails. Only ever true
    // for --system: a user's own PATH needs no elevation on any platform,
    // Windows included, because the user PATH lives under HKCU.
    if (plan.needsElevation) {
      Logger.log(Platform.isWindows
          ? 'Changing the PATH for every user needs an administrator '
              'terminal. Right-click your terminal and choose "Run as '
              'administrator", then run this again.'
          : 'Changing the PATH for every user needs root. Run this again '
              'with sudo.');
    }

    if (argResults!['dry-run'] as bool) {
      _describe(plan);
      return;
    }

    if (plan.platform == PathPlatform.windows) {
      await _applyWindows(plan);
    } else {
      _applyPosix(plan);
    }

    Logger.log('');
    Logger.log('Open a new terminal, or run this to use it now:');
    Logger.log(plan.platform == PathPlatform.windows
        ? r'  $env:Path += ";' '$directory"'
        : '  export PATH="\$PATH:$directory"');
  }

  void _describe(EnsurePathPlan plan) {
    Logger.log('Would add ${plan.directory} to your PATH.');
    for (final target in plan.targets) {
      Logger.log('  ${target.file}');
      Logger.log('    ${target.line}');
    }
    if (plan.command.isNotEmpty) {
      Logger.log('  powershell -NoProfile -Command "${plan.command}"');
    }
  }

  void _applyPosix(EnsurePathPlan plan) {
    for (final target in plan.targets) {
      final file = File(target.file);
      final existing = file.existsSync() ? file.readAsStringSync() : '';

      // A second run must not append a second line. The marker is what makes
      // this safe to run as often as anyone likes.
      if (ensurePathAlreadyWritten(existing, target.marker)) {
        Logger.log('${target.file} already has it.');
        continue;
      }

      final needsNewline = existing.isNotEmpty && !existing.endsWith('\n');
      file.writeAsStringSync(
        '${needsNewline ? '\n' : ''}${target.line}\n',
        mode: FileMode.append,
      );
      Logger.log('Added to ${target.file}.');
    }
  }

  Future<void> _applyWindows(EnsurePathPlan plan) async {
    final result = await Process.run(
      'powershell',
      <String>['-NoProfile', '-Command', plan.command],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      Logger.error('Could not change the PATH: ${result.stderr}');
      exit(1);
    }
    Logger.log('Added ${plan.directory} to your ${plan.scope.name} PATH.');
  }

  PathPlatform _platform() {
    if (Platform.isWindows) return PathPlatform.windows;
    if (Platform.isMacOS) return PathPlatform.macos;
    return PathPlatform.linux;
  }

  /// The directory holding this executable.
  ///
  /// `Platform.resolvedExecutable` rather than `Platform.script`: in a
  /// compiled binary the script URI is a data URI, and the whole point of
  /// this command is the compiled binary.
  String? _selfDirectory() {
    try {
      return p.dirname(File(Platform.resolvedExecutable).absolute.path);
    } on Object {
      return null;
    }
  }
}
