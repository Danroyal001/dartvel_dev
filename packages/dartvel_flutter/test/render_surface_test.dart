// Where the application's frames are landing, as the running app can observe
// it. `NEW_SPEC.md` § Terminal Rendering.
//
// The point of putting this on DV.Platform rather than in a namespace of its
// own is that a terminal is another thing the platform reports on, like a
// screen size or a device type. Application code that needs to know asks; code
// that does not should never have to branch. What the terminal backend
// attaches (its size, its graphics) belongs to the package that installs it;
// the framework keeps it behind DVAttachedSurface.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _Attached implements DVAttachedSurface {
  bool disposed = false;

  @override
  void dispose() => disposed = true;
}

void main() {
  tearDown(() => DV.Platform.useRenderSurface(null));

  group('DV.Platform.surface', () {
    test('is the GUI by default', () {
      // The default on every target. An application that asked for nothing
      // gets the surface it has always had.
      expect(DV.Platform.surface, DVRenderSurface.gui);
    });

    test('reports the terminal when the terminal backend is active', () {
      // Set by the runtime at startup from what was linked at build time --
      // never resolved by probing, because the presentation is a build-time
      // decision and probing would make it a runtime one.
      DV.Platform.useRenderSurface(DVRenderSurface.terminal);
      expect(DV.Platform.surface, DVRenderSurface.terminal);
    });

    test('nothing is attached unless the surface is a terminal', () {
      expect(DV.Platform.attachedSurface, isNull);
    });

    test('what the backend attached is kept while the surface is a terminal', () {
      final _Attached attached = _Attached();
      DV.Platform.useRenderSurface(DVRenderSurface.terminal, attached: attached);
      expect(DV.Platform.attachedSurface, same(attached));
    });

    test('a GUI surface clears what was attached', () {
      // Switching back must not leave a stale terminal describing a window.
      DV.Platform.useRenderSurface(DVRenderSurface.terminal, attached: _Attached());
      DV.Platform.useRenderSurface(DVRenderSurface.gui);
      expect(DV.Platform.surface, DVRenderSurface.gui);
      expect(DV.Platform.attachedSurface, isNull);
    });

    test('an attachment given to a GUI surface is not kept', () {
      DV.Platform.useRenderSurface(DVRenderSurface.gui, attached: _Attached());
      expect(DV.Platform.attachedSurface, isNull);
    });
  });
}
