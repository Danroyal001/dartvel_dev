import 'dart:async';

/// How faithfully a terminal can draw.
///
/// Kitty's graphics protocol carries real pixels; ANSI carries cells and is
/// coarser. Which one is active is reported rather than inferred from a
/// terminal's name, because the name is a poor predictor and a wrong guess
/// changes what a layout can reasonably draw.
enum DVTerminalGraphics { kitty, ansi }

/// The default identifier for a graphics query.
///
/// Any small number does; it exists only so a reply can be matched to the
/// question that provoked it rather than to something another program left
/// in the same terminal.
const int dvGraphicsQueryId = 31;

/// The escape sequence that asks a terminal whether it speaks the Kitty
/// graphics protocol, followed by a primary Device Attributes request.
///
/// The pairing is what makes the answer arrive promptly. A terminal with no
/// graphics support says nothing to the first sequence and answers the second
/// one, so a negative answer is a reply rather than a timeout — otherwise
/// every ANSI terminal would stall startup for the length of the wait.
///
/// The image is one transparent pixel described inline (`a=q` query, `t=d`
/// direct payload, `f=24` RGB, one column by one row), which is the smallest
/// well-formed thing a terminal can be asked to accept.
String dvKittyGraphicsQuery([int id = dvGraphicsQueryId]) =>
    '\x1b_Gi=$id,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\\x1b[c';

final RegExp _apcGraphics = RegExp(r'\x1b_G(.*?)\x1b\\', dotAll: true);
final RegExp _deviceAttributes = RegExp(r'\x1b\[\?[0-9;]*c');

/// What a terminal's answer to [dvKittyGraphicsQuery] means, or null while
/// the answer is still arriving.
///
/// Null is the state that matters. Terminal replies arrive in whatever pieces
/// the pty hands over, and treating a partial one as "no acknowledgement"
/// would report every Kitty terminal as an ANSI one — the graphics reply is
/// always mid-flight before the device attributes land.
///
/// Anything other than `OK` from a matching query is read as no support. A
/// terminal that parsed the escape and declined it will not draw the pixels
/// either, and sending them anyway paints the escape sequence across the
/// screen as literal text, which is worse than drawing coarser cells.
DVTerminalGraphics? dvReadGraphicsReply(
  String reply, {
  int id = dvGraphicsQueryId,
}) {
  for (final RegExpMatch match in _apcGraphics.allMatches(reply)) {
    final String body = match.group(1) ?? '';
    final int separator = body.indexOf(';');
    if (separator < 0) continue;
    final List<String> keys = body.substring(0, separator).split(',');
    // A reply for another identifier belongs to an earlier query or to another
    // program sharing this terminal. Believing it would report pixel graphics
    // on a terminal that never answered.
    if (!keys.contains('i=$id')) continue;
    return body.substring(separator + 1).trim() == 'OK'
        ? DVTerminalGraphics.kitty
        : DVTerminalGraphics.ansi;
  }
  if (_deviceAttributes.hasMatch(reply)) return DVTerminalGraphics.ansi;
  return null;
}

/// Asks the terminal which graphics protocol it speaks.
///
/// [write] and [replies] are the two halves of the terminal, passed in so the
/// negotiation can be exercised without a pty: every branch here is one an
/// application hits at startup on somebody's machine, and none of them would
/// otherwise be reachable by a test.
///
/// With no terminal attached nothing is written at all. stdout redirected to a
/// file or a pipe is the common case, and putting an APC escape into it
/// corrupts whatever is reading the output while getting no answer back.
Future<DVTerminalGraphics> dvNegotiateTerminalGraphics({
  required bool hasTerminal,
  required void Function(String) write,
  required Stream<String> replies,
  int id = dvGraphicsQueryId,
  Duration timeout = const Duration(milliseconds: 300),
}) async {
  if (!hasTerminal) return DVTerminalGraphics.ansi;
  try {
    write(dvKittyGraphicsQuery(id));
  } on Object {
    // A closed or broken output. There is nothing to negotiate with.
    return DVTerminalGraphics.ansi;
  }

  final Completer<DVTerminalGraphics> answered =
      Completer<DVTerminalGraphics>();
  final StringBuffer seen = StringBuffer();
  void settle(DVTerminalGraphics value) {
    if (!answered.isCompleted) answered.complete(value);
  }

  // A terminal that answers neither sequence still has to let startup carry
  // on. Some multiplexers and some ssh servers swallow both.
  final Timer deadline = Timer(timeout, () => settle(DVTerminalGraphics.ansi));
  final StreamSubscription<String> listening = replies.listen(
    (String chunk) {
      seen.write(chunk);
      final DVTerminalGraphics? answer =
          dvReadGraphicsReply(seen.toString(), id: id);
      if (answer != null) settle(answer);
    },
    onError: (Object _) => settle(DVTerminalGraphics.ansi),
    onDone: () => settle(DVTerminalGraphics.ansi),
    cancelOnError: false,
  );

  try {
    return await answered.future;
  } finally {
    deadline.cancel();
    unawaited(listening.cancel());
  }
}
