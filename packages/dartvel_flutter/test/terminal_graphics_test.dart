// Which graphics protocol a terminal speaks, asked rather than guessed.
//
// DVTerminalGraphics has existed since terminal rendering was first sketched
// and nothing ever produced a value for it: every constructor took one as an
// argument and the only callers were tests, so `DV.Platform.terminal.graphics`
// reported whatever a caller had typed. A layout deciding between real pixels
// and coloured cells was reading a constant.
//
// The terminal's own answer is the only honest source. Guessing from TERM or
// TERM_PROGRAM is what the specification rules out, and it is wrong often
// enough to matter: tmux and screen rewrite TERM, WezTerm and Ghostty and
// Konsole all speak the protocol under names nothing would match, and a
// terminal claiming to be xterm-kitty inside an ssh session to a host that
// strips APC sequences is not one.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Kitty graphics protocol acknowledgement for [id].
String kittyOk(int id) => '\x1b_Gi=$id;OK\x1b\\';

/// A primary Device Attributes reply — what every terminal answers, whether
/// or not it understood the graphics query sent alongside it.
const String deviceAttributes = '\x1b[?62;1;6c';

void main() {
  group('reading a terminal reply', () {
    test('an acknowledgement for this query means the protocol is spoken', () {
      expect(
        dvReadGraphicsReply(kittyOk(31), id: 31),
        DVTerminalGraphics.kitty,
      );
    });

    test('device attributes with no acknowledgement means cells', () {
      expect(
        dvReadGraphicsReply(deviceAttributes, id: 31),
        DVTerminalGraphics.ansi,
      );
    });

    test('a half-arrived reply is not an answer yet', () {
      // The escape has begun and the terminating string terminator has not
      // arrived. Reading this as "no acknowledgement" would call every Kitty
      // terminal an ANSI one, because the graphics reply always arrives in
      // pieces before the device attributes do.
      expect(dvReadGraphicsReply('\x1b_Gi=31;O', id: 31), isNull);
      expect(dvReadGraphicsReply('', id: 31), isNull);
    });

    test('an acknowledgement for somebody else is not an answer', () {
      // A reply left over from an earlier query, or from another program
      // sharing the terminal. Believing it would report Kitty graphics on a
      // terminal that never answered.
      expect(dvReadGraphicsReply(kittyOk(7), id: 31), isNull);
      expect(
        dvReadGraphicsReply('${kittyOk(7)}$deviceAttributes', id: 31),
        DVTerminalGraphics.ansi,
      );
    });

    test('a refusal is a refusal, however it is spelt', () {
      // A terminal that parsed the escape and declined it. Sending it pixels
      // anyway paints the escape sequence across the screen as text, which is
      // a far worse outcome than drawing coarser cells.
      expect(
        dvReadGraphicsReply('\x1b_Gi=31;ENOTSUPPORTED:nope\x1b\\', id: 31),
        DVTerminalGraphics.ansi,
      );
    });
  });

  group('asking the terminal', () {
    test('a terminal that acknowledges gets pixels', () async {
      final replies = StreamController<String>();
      final Future<DVTerminalGraphics> answer = dvNegotiateTerminalGraphics(
        hasTerminal: true,
        write: (_) {},
        replies: replies.stream,
        id: 31,
      );
      replies.add(kittyOk(31));
      expect(await answer, DVTerminalGraphics.kitty);
      await replies.close();
    });

    test('a terminal that ignores the query still ends the wait', () async {
      // The graphics query is paired with a device attributes request for
      // exactly this reason. Without the pairing a terminal with no Kitty
      // support says nothing at all, and startup stalls for the whole timeout
      // on every ANSI terminal there is.
      final replies = StreamController<String>();
      final Stopwatch clock = Stopwatch()..start();
      final Future<DVTerminalGraphics> answer = dvNegotiateTerminalGraphics(
        hasTerminal: true,
        write: (_) {},
        replies: replies.stream,
        id: 31,
        timeout: const Duration(seconds: 30),
      );
      replies.add(deviceAttributes);
      expect(await answer, DVTerminalGraphics.ansi);
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
      await replies.close();
    });

    test('a reply arriving in pieces is read as one answer', () async {
      final replies = StreamController<String>();
      final Future<DVTerminalGraphics> answer = dvNegotiateTerminalGraphics(
        hasTerminal: true,
        write: (_) {},
        replies: replies.stream,
        id: 31,
      );
      replies.add('\x1b_Gi=31');
      replies.add(';OK\x1b');
      replies.add('\\');
      expect(await answer, DVTerminalGraphics.kitty);
      await replies.close();
    });

    test('a terminal that says nothing at all is cells, not a hang', () async {
      final replies = StreamController<String>();
      expect(
        await dvNegotiateTerminalGraphics(
          hasTerminal: true,
          write: (_) {},
          replies: replies.stream,
          id: 31,
          timeout: const Duration(milliseconds: 40),
        ),
        DVTerminalGraphics.ansi,
      );
      await replies.close();
    });

    test('nothing is written when there is no terminal to write to', () async {
      // stdout redirected to a file or a pipe. Writing the query there puts
      // an APC escape into the application's own output, which corrupts
      // whatever was reading it and gets no answer back either way.
      final List<String> written = <String>[];
      expect(
        await dvNegotiateTerminalGraphics(
          hasTerminal: false,
          write: written.add,
          replies: const Stream<String>.empty(),
        ),
        DVTerminalGraphics.ansi,
      );
      expect(written, isEmpty);
    });

    test('the query is written once, before any answer is read', () async {
      final List<String> written = <String>[];
      final replies = StreamController<String>();
      final Future<DVTerminalGraphics> answer = dvNegotiateTerminalGraphics(
        hasTerminal: true,
        write: written.add,
        replies: replies.stream,
        id: 31,
      );
      expect(written, hasLength(1));
      replies.add(deviceAttributes);
      await answer;
      expect(written, hasLength(1));
      await replies.close();
    });
  });

  test('an attached terminal carries the graphics it negotiated', () async {
    // The whole point of the negotiation: the surface an application reads
    // through DV.Platform.terminal reports what the terminal answered, not a
    // value someone passed in.
    final DVTerminalSurface surface = await DVTerminalSurface.attach(
      negotiate: () async => DVTerminalGraphics.kitty,
    );
    addTearDown(surface.dispose);
    expect(surface.graphics, DVTerminalGraphics.kitty);
  });
}
