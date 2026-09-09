import 'terminal_graphics.dart';

/// No terminal in a browser, so nothing to negotiate with.
Future<DVTerminalGraphics> dvNegotiateAttachedTerminalGraphics({
  Duration timeout = const Duration(milliseconds: 300),
}) async =>
    DVTerminalGraphics.ansi;
