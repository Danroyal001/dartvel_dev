import 'dart:convert';
import 'dart:io';

import 'terminal_graphics.dart';

/// Asks the terminal this process is attached to which graphics protocol it
/// speaks.
///
/// Both halves have to be a terminal. A process with stdout on a pty and stdin
/// on a pipe can send the query and can never hear the answer, so it would
/// wait out the whole timeout on every start.
///
/// The reply is a control sequence, so echo and line buffering are turned off
/// for the length of the question and restored afterwards. Leaving a terminal
/// in raw mode is the failure people notice: the shell they return to stops
/// showing what they type.
Future<DVTerminalGraphics> dvNegotiateAttachedTerminalGraphics({
  Duration timeout = const Duration(milliseconds: 300),
}) async {
  if (!stdout.hasTerminal || !stdin.hasTerminal) {
    return DVTerminalGraphics.ansi;
  }

  final bool echo = stdin.echoMode;
  final bool lines = stdin.lineMode;
  try {
    stdin.echoMode = false;
    stdin.lineMode = false;
  } on Object {
    // A terminal that will not go raw cannot be asked; it is not a failure.
    return DVTerminalGraphics.ansi;
  }

  try {
    return await dvNegotiateTerminalGraphics(
      hasTerminal: true,
      write: stdout.write,
      // latin1 rather than utf8: the answer is a control sequence, and a
      // decoder that substitutes replacement characters for bytes it dislikes
      // would rewrite the very escapes being matched.
      replies: stdin.transform(latin1.decoder),
      timeout: timeout,
    );
  } on Object {
    return DVTerminalGraphics.ansi;
  } finally {
    try {
      stdin.echoMode = echo;
      stdin.lineMode = lines;
    } on Object {
      // Nothing useful to do; the process is leaving either way.
    }
  }
}
