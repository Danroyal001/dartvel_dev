import 'dart:io';

import 'terminal_size.dart';

/// The size of the terminal this process is attached to; 80 by 24 where
/// there is none, as every terminal program has assumed since there were
/// terminals.
DVTerminalSize dvReadAttachedTerminalSize() {
  try {
    if (stdout.hasTerminal) {
      return DVTerminalSize(columns: stdout.terminalColumns, rows: stdout.terminalLines);
    }
  } on Object {
    // Not a terminal after all, or one that will not say.
  }
  return const DVTerminalSize(columns: 80, rows: 24);
}

/// One event per window-change signal -- SIGWINCH -- and none on a platform
/// that has no such signal.
Stream<void> dvTerminalWindowChanges() {
  if (Platform.isWindows) return const Stream<void>.empty();
  try {
    return ProcessSignal.sigwinch.watch();
  } on Object {
    return const Stream<void>.empty();
  }
}

/// Whether this process can open a window: on Linux, a display server named
/// by the environment; on a desktop OS, always.
bool dvDisplayAvailable() => dvDisplayAvailableIn(Platform.environment, os: Platform.operatingSystem);
