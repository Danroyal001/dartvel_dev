/// Putting the `dartvel` command on the PATH.
///
/// A binary downloaded from a release lands wherever the browser put it. It
/// runs from there, and then the next terminal cannot find it, which reads as
/// a broken install rather than an unset variable.
///
/// One thing worth stating plainly, because the opposite is widely assumed:
/// **Windows does not need administrator rights for this.** The *user* PATH
/// lives under `HKCU` and any process can write it. Only the *machine* PATH,
/// under `HKLM`, needs elevation, and a single-user install has no reason to
/// touch it. So user scope is the default on every platform and nothing
/// elevates unless `--system` is asked for.
library;

/// The platforms this has to behave differently on.
enum PathPlatform { linux, macos, windows }

/// Whose PATH is being changed.
enum PathScope {
  /// The current user. Writable without elevation everywhere.
  user,

  /// Every user. Needs administrator on Windows and root elsewhere.
  system,
}

/// A file to append a line to.
class PathTarget {
  const PathTarget({
    required this.file,
    required this.line,
    required this.marker,
  });

  /// The shell startup file.
  final String file;

  /// The line to append, marker included.
  final String line;

  /// What a second run looks for, so this is written once.
  final String marker;
}

/// What `dartvel ensure-path` would do.
class EnsurePathPlan {
  const EnsurePathPlan({
    required this.directory,
    required this.platform,
    required this.scope,
    required this.alreadyPresent,
    required this.targets,
    required this.command,
    required this.needsElevation,
  });

  final String directory;
  final PathPlatform platform;
  final PathScope scope;

  /// Whether the directory is already on the PATH.
  final bool alreadyPresent;

  /// Files to append to, on POSIX. Empty on Windows, which uses [command].
  final List<PathTarget> targets;

  /// The command to run, on Windows. Empty elsewhere.
  final String command;

  /// Whether this needs elevation. Only ever true for system scope.
  final bool needsElevation;

  bool get changesNeeded => !alreadyPresent;
}

/// The marker a written line carries, so a second run recognises its own work.
const String _marker = '# added by dartvel ensure-path';

/// Whether [contents] already carries a line written by this command.
bool ensurePathAlreadyWritten(String contents, String marker) =>
    contents.contains(marker);

/// Resolve what putting [directory] on the PATH requires.
EnsurePathPlan ensurePathPlan({
  required String directory,
  required String currentPath,
  required PathPlatform platform,
  PathScope scope = PathScope.user,
  String? shell,
  String? home,
}) {
  final windows = platform == PathPlatform.windows;
  final separator = windows ? ';' : ':';

  // Compared entry by entry rather than by substring: `/usr/local/bin2`
  // contains `/usr/local/bin` and is a different directory. Trailing
  // separators are stripped because PATH entries are written both ways and
  // mean the same place.
  String normalise(String value) {
    var out = value.trim();
    while (out.length > 1 &&
        (out.endsWith('/') || (windows && out.endsWith(r'\')))) {
      out = out.substring(0, out.length - 1);
    }
    // Windows paths are case-insensitive; POSIX paths are not, and treating
    // them as though they were would call ~/Bin present when only ~/bin is.
    return windows ? out.toLowerCase() : out;
  }

  final wanted = normalise(directory);
  final present = currentPath
      .split(separator)
      .where((String entry) => entry.trim().isNotEmpty)
      .map(normalise)
      .contains(wanted);

  if (windows) {
    return EnsurePathPlan(
      directory: directory,
      platform: platform,
      scope: scope,
      alreadyPresent: present,
      targets: const <PathTarget>[],
      // Not `setx`. It caps the value at 1024 characters and silently
      // truncates the rest, which destroys a PATH rather than extending it.
      // The .NET call has no such limit.
      command: _windowsCommand(directory, scope),
      needsElevation: scope == PathScope.system,
    );
  }

  return EnsurePathPlan(
    directory: directory,
    platform: platform,
    scope: scope,
    alreadyPresent: present,
    targets: <PathTarget>[
      PathTarget(
        file: _rcFile(platform, shell, home ?? '~'),
        // Appends rather than assigns: a line that sets PATH outright removes
        // every other tool from the shell. Quoted, so a directory with a space
        // in it survives.
        line: 'export PATH="\$PATH:$directory"  $_marker',
        marker: _marker,
      ),
    ],
    command: '',
    // Nothing here needs root: a user's own rc file is theirs.
    needsElevation: scope == PathScope.system,
  );
}

/// The startup file the user's shell actually reads.
///
/// Read from the shell rather than guessed. Appending to `.bashrc` for a zsh
/// user changes a file they will never read, and the command would report
/// success.
String _rcFile(PathPlatform platform, String? shell, String home) {
  final name = (shell ?? (platform == PathPlatform.macos ? 'zsh' : 'bash'))
      .split('/')
      .last;
  return switch (name) {
    'zsh' => '$home/.zshrc',
    'bash' => '$home/.bashrc',
    // Anything else gets .profile, which most shells read, rather than
    // nothing at all.
    _ => '$home/.profile',
  };
}

String _windowsCommand(String directory, PathScope scope) {
  final target = scope == PathScope.system ? 'Machine' : 'User';
  final escaped = directory.replaceAll("'", "''");
  return "[Environment]::SetEnvironmentVariable('Path', "
      "([Environment]::GetEnvironmentVariable('Path','$target') + "
      "';$escaped'), '$target')";
}
