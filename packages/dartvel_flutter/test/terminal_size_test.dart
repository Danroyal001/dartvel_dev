// The terminal's size, as a signal.
//
// The spec: `DV.Platform.terminal.size` is a signal, so a layout responds to
// a resized terminal through the same reactive path a resized window uses.
// The size comes from the terminal the process is attached to and changes
// when the terminal tells the process it changed -- SIGWINCH on POSIX. What
// the tests hold to: the surface reads its size once and reports it; a
// resize signal makes it read again and notify; a surface built for a
// process with no terminal has a sensible size and never throws.
import 'dart:async';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads its size once, and columns and rows are that size', () {
    final DVTerminalSurface t = DVTerminalSurface(
      graphics: DVTerminalGraphics.ansi,
      read: () => const DVTerminalSize(columns: 120, rows: 40),
      resizes: const Stream<void>.empty(),
    );
    addTearDown(t.dispose);
    expect(t.size.value, const DVTerminalSize(columns: 120, rows: 40));
    expect(t.columns, 120);
    expect(t.rows, 40);
  });

  test('a resize makes it read again, and listeners hear it', () async {
    DVTerminalSize current = const DVTerminalSize(columns: 80, rows: 24);
    final StreamController<void> resizes = StreamController<void>();
    final DVTerminalSurface t = DVTerminalSurface(
      graphics: DVTerminalGraphics.kitty,
      read: () => current,
      resizes: resizes.stream,
    );
    addTearDown(t.dispose);
    final List<DVTerminalSize> seen = <DVTerminalSize>[];
    t.size.addListener(() => seen.add(t.size.value));

    current = const DVTerminalSize(columns: 200, rows: 50);
    resizes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(seen, <DVTerminalSize>[const DVTerminalSize(columns: 200, rows: 50)]);

    // The same size again is not a change.
    resizes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    await resizes.close();
  });

  test('the process\'s own terminal, when it has none, is 80 by 24 and never throws', () {
    if (stdout.hasTerminal) {
      markTestSkipped('this process is attached to a terminal; the fallback is not in play');
      return;
    }
    final DVTerminalSurface t = DVTerminalSurface.attached(graphics: DVTerminalGraphics.ansi);
    addTearDown(t.dispose);
    expect(t.size.value, const DVTerminalSize(columns: 80, rows: 24));
  });

  test('on POSIX a window-change signal is a resize', () async {
    if (Platform.isWindows) {
      markTestSkipped('SIGWINCH is POSIX');
      return;
    }
    int reads = 0;
    final DVTerminalSurface t = DVTerminalSurface(
      graphics: DVTerminalGraphics.ansi,
      read: () => DVTerminalSize(columns: 80 + reads++, rows: 24),
      resizes: DVTerminalSurface.windowChanges(),
    );
    addTearDown(t.dispose);
    expect(t.size.value.columns, 80);
    Process.killPid(pid, ProcessSignal.sigwinch);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(t.size.value.columns, 81);
  });

  test('DV.Platform.terminal carries the signal', () {
    final DVTerminalSurface t = DVTerminalSurface(
      graphics: DVTerminalGraphics.ansi,
      read: () => const DVTerminalSize(columns: 100, rows: 30),
      resizes: const Stream<void>.empty(),
    );
    addTearDown(() {
      DV.Platform.useRenderSurface(null);
      t.dispose();
    });
    DV.Platform.useRenderSurface(DVRenderSurface.terminal, terminal: t);
    expect(DV.Platform.terminal!.size.value.columns, 100);
    expect(DV.Platform.terminal!.graphics, DVTerminalGraphics.ansi);
  });
}
