// Correlating the two ideas of a display.
//
// Choosing the projector needs a name and a primary flag, which only the
// window system reports (DVDisplay). Putting a window fullscreen on it needs
// Flutter's Display, which has a size, a device pixel ratio and an id, and
// neither a name nor a position. Nothing links them, so they have to be
// matched, and a wrong match sends the output to the wrong screen.
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

DVDisplay display(String id, String name, Rect bounds,
        {bool primary = false, double dpr = 1.0}) =>
    DVDisplay(
      id: id,
      name: name,
      bounds: bounds,
      devicePixelRatio: dpr,
      isPrimary: primary,
    );

void main() {
  final laptop = display('x11-0', 'eDP-1', const Rect.fromLTWH(0, 0, 1280, 800),
      primary: true);
  final projector =
      display('x11-1', 'HDMI-1', const Rect.fromLTWH(1280, 0, 1920, 1080));

  test('matches on size when the size is unique', () {
    final match = DVDisplays.matchEngineDisplay(
      target: projector,
      all: <DVDisplay>[laptop, projector],
      engine: const <DVEngineDisplay>[
        DVEngineDisplay(id: 7, size: Size(1280, 800), devicePixelRatio: 1),
        DVEngineDisplay(id: 9, size: Size(1920, 1080), devicePixelRatio: 1),
      ],
    );

    expect(match?.id, 9);
  });

  test('matches on device pixel ratio too, so a scaled twin is not confused',
      () {
    final scaled = display('x11-2', 'HDMI-2',
        const Rect.fromLTWH(0, 0, 1920, 1080), dpr: 2.0);

    final match = DVDisplays.matchEngineDisplay(
      target: scaled,
      all: <DVDisplay>[projector, scaled],
      engine: const <DVEngineDisplay>[
        DVEngineDisplay(id: 1, size: Size(1920, 1080), devicePixelRatio: 1),
        DVEngineDisplay(id: 2, size: Size(1920, 1080), devicePixelRatio: 2),
      ],
    );

    expect(match?.id, 2);
  });

  test('falls back to position in OS order when two displays are identical',
      () {
    // Two of the same projector is a normal signage setup, and size cannot
    // tell them apart. Index is the only remaining signal, and it is a guess
    // the caller should be told about rather than a fact.
    final second =
        display('x11-2', 'HDMI-2', const Rect.fromLTWH(1920, 0, 1920, 1080));

    final match = DVDisplays.matchEngineDisplay(
      target: second,
      all: <DVDisplay>[projector, second],
      engine: const <DVEngineDisplay>[
        DVEngineDisplay(id: 1, size: Size(1920, 1080), devicePixelRatio: 1),
        DVEngineDisplay(id: 2, size: Size(1920, 1080), devicePixelRatio: 1),
      ],
    );

    expect(match?.id, 2);
  });

  test('returns null when the engine reports a different number of displays',
      () {
    // The two lists disagree, so index means nothing and size is ambiguous.
    // Guessing here puts the lyrics on the wrong screen.
    final match = DVDisplays.matchEngineDisplay(
      target: projector,
      all: <DVDisplay>[laptop, projector],
      engine: const <DVEngineDisplay>[
        DVEngineDisplay(id: 1, size: Size(1920, 1080), devicePixelRatio: 1),
        DVEngineDisplay(id: 2, size: Size(1920, 1080), devicePixelRatio: 1),
        DVEngineDisplay(id: 3, size: Size(1920, 1080), devicePixelRatio: 1),
      ],
    );

    expect(match, isNull);
  });

  test('returns null when nothing matches and the counts give no order', () {
    final match = DVDisplays.matchEngineDisplay(
      target: projector,
      all: <DVDisplay>[projector],
      engine: const <DVEngineDisplay>[],
    );

    expect(match, isNull);
  });

  test('a target that is not in the list is not matched by accident', () {
    final stranger =
        display('x11-9', 'VGA-1', const Rect.fromLTWH(0, 0, 800, 600));

    final match = DVDisplays.matchEngineDisplay(
      target: stranger,
      all: <DVDisplay>[laptop, projector],
      engine: const <DVEngineDisplay>[
        DVEngineDisplay(id: 1, size: Size(1280, 800), devicePixelRatio: 1),
        DVEngineDisplay(id: 2, size: Size(1920, 1080), devicePixelRatio: 1),
      ],
    );

    expect(match, isNull);
  });
}
