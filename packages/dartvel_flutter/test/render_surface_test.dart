// Where the application's frames are landing, as the running app can observe
// it. `NEW_SPEC.md` § Terminal Rendering.
//
// The point of putting this on DV.Platform rather than in a namespace of its
// own is that a terminal is another thing the platform reports on, like a
// screen size or a device type. Application code that needs to know asks; code
// that does not should never have to branch.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DV.Platform.surface', () {
    test('is the GUI by default', () {
      // The default on every target. An application that asked for nothing
      // gets the surface it has always had.
      expect(DV.Platform.surface, DVRenderSurface.gui);
    });

    test('reports the terminal when the terminal backend is active', () {
      // Set by the runtime at startup from what was linked at build time —
      // never resolved by probing, because the presentation is a build-time
      // decision and probing would make it a runtime one.
      DV.Platform.useRenderSurface(DVRenderSurface.terminal);
      addTearDown(() => DV.Platform.useRenderSurface(null));

      expect(DV.Platform.surface, DVRenderSurface.terminal);
    });

    test('terminal details are null unless the surface is a terminal', () {
      // Asking for terminal size in a window is a question with no answer, and
      // a fabricated one would be worse than none.
      expect(DV.Platform.terminal, isNull);
    });

    test('terminal details exist when the surface is a terminal', () {
      DV.Platform.useRenderSurface(
        DVRenderSurface.terminal,
        terminal: const DVTerminalSurface(
          columns: 120,
          rows: 40,
          graphics: DVTerminalGraphics.kitty,
        ),
      );
      addTearDown(() => DV.Platform.useRenderSurface(null));

      final terminal = DV.Platform.terminal;
      expect(terminal, isNotNull);
      expect(terminal!.columns, 120);
      expect(terminal.rows, 40);
      expect(terminal.graphics, DVTerminalGraphics.kitty);
    });

    test('graphics mode is reported, never guessed', () {
      // Full fidelity needs Kitty; ANSI cells are the fallback. Which one is
      // active decides what a layout can reasonably draw, so it is reported
      // rather than inferred from the terminal name.
      DV.Platform.useRenderSurface(
        DVRenderSurface.terminal,
        terminal: const DVTerminalSurface(
          columns: 80,
          rows: 24,
          graphics: DVTerminalGraphics.ansi,
        ),
      );
      addTearDown(() => DV.Platform.useRenderSurface(null));

      expect(DV.Platform.terminal!.graphics, DVTerminalGraphics.ansi);
    });

    test('a GUI surface clears any terminal details', () {
      // Switching back must not leave a stale terminal describing a window.
      DV.Platform.useRenderSurface(
        DVRenderSurface.terminal,
        terminal: const DVTerminalSurface(
          columns: 80,
          rows: 24,
          graphics: DVTerminalGraphics.ansi,
        ),
      );
      DV.Platform.useRenderSurface(DVRenderSurface.gui);
      addTearDown(() => DV.Platform.useRenderSurface(null));

      expect(DV.Platform.surface, DVRenderSurface.gui);
      expect(DV.Platform.terminal, isNull);
    });
  });
}
