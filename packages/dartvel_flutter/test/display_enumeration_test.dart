// DV.Window.displays: where the display list actually comes from.
//
// Two sources, and which one is used is the thing to get right. A
// `window.displays` native binding knows what the OS knows -- layout origins,
// panel names, which display is primary. Without it, Flutter's own
// PlatformDispatcher.displays still reports size, pixel ratio and refresh rate
// for every display, and unlike the desktop windowing API it is stable and
// unflagged. Preferring the poorer source when the richer one is registered
// would quietly lose the names a kiosk deployment addresses displays by.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(DVWindowManager.reset);
  tearDown(() {
    DVNativeBridge.unregister('window.displays');
    DVWindowManager.reset();
  });

  DVWindowManager manager() => DV.Platform.Window;

  test('displays start empty, before anything has enumerated them', () {
    expect(manager().displays.value, isEmpty);
  });

  test('with no binding it falls back to what Flutter reports', () async {
    // The point of the fallback: a desktop build with no native binding still
    // knows the size and pixel ratio of the screen it is on.
    final List<DVDisplay> displays = await manager().refreshDisplays();

    expect(displays, isNotEmpty,
        reason: 'the test binding always has at least one display');
    expect(displays.first.bounds.width, greaterThan(0));
    expect(displays.first.hasLayout, isFalse,
        reason: 'Flutter reports no layout origin');
    expect(displays.first.isPrimary, isFalse,
        reason: 'Flutter does not say which display is primary, and a guess '
            'is what DVDisplayHint.secondary would then build on');
  });

  test('a registered binding is preferred over Flutter', () async {
    DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
          <String, Object?>{
            'id': 'A',
            'width': 1920.0,
            'height': 1080.0,
            'devicePixelRatio': 1.0,
            'name': 'Operator',
            'isPrimary': true,
            'left': 0.0,
            'top': 0.0,
          },
          <String, Object?>{
            'id': 'B',
            'width': 1920.0,
            'height': 1080.0,
            'devicePixelRatio': 1.0,
            'name': 'Customer',
            'left': 1920.0,
            'top': 0.0,
          },
        ]);

    final List<DVDisplay> displays = await manager().refreshDisplays();

    expect(displays.map((DVDisplay d) => d.name), <String>['Operator', 'Customer']);
    expect(displays.last.hasLayout, isTrue);
    expect(displays.last.bounds.left, 1920);
  });

  test('refreshing publishes to the signal, so a workspace can react',
      () async {
    // The contract: capability is a snapshot plus a signal for the two things
    // that change at runtime, so a "move to display" control can disappear the
    // moment the display is unplugged.
    final List<int> counts = <int>[];
    void listener() => counts.add(manager().displays.value.length);
    manager().displays.addListener(listener);
    addTearDown(() => manager().displays.removeListener(listener));

    DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
          <String, Object?>{'id': 'A', 'width': 800.0, 'height': 600.0},
          <String, Object?>{'id': 'B', 'width': 800.0, 'height': 600.0},
        ]);
    await manager().refreshDisplays();

    DVNativeBridge.unregister('window.displays');
    DVNativeBridge.register(
        'window.displays',
        (Object? _) => <Object?>[
              <String, Object?>{'id': 'A', 'width': 800.0, 'height': 600.0},
            ]);
    await manager().refreshDisplays();

    expect(counts, <int>[2, 1]);
  });

  test('device profile names win over the panel name', () async {
    DVWindowManager.displayNames = <String, String>{'B': 'Signage'};
    DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
          <String, Object?>{
            'id': 'B',
            'width': 800.0,
            'height': 600.0,
            'name': 'DELL U2412M',
          },
        ]);

    final List<DVDisplay> displays = await manager().refreshDisplays();
    expect(displays.single.name, 'Signage');
  });

  test('a binding that throws does not take the application down', () async {
    // A display enumeration failure must cost the display list, not the launch.
    DVNativeBridge.register(
        'window.displays', (Object? _) => throw StateError('no display server'));

    expect(await manager().refreshDisplays(), isEmpty);
  });

  test('capability.displays is false with one display and true with two',
      () async {
    DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
          <String, Object?>{'id': 'A', 'width': 800.0, 'height': 600.0},
        ]);
    await manager().refreshDisplays();
    expect(manager().capability.displays, isFalse);

    DVNativeBridge.unregister('window.displays');
    DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
          <String, Object?>{'id': 'A', 'width': 800.0, 'height': 600.0},
          <String, Object?>{'id': 'B', 'width': 800.0, 'height': 600.0},
        ]);
    await manager().refreshDisplays();
    expect(manager().capability.displays, isTrue,
        reason: 'more than one display is addressable');
  });

  test('reset clears the display list, so tests cannot see each others',
      () async {
    DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
          <String, Object?>{'id': 'A', 'width': 800.0, 'height': 600.0},
        ]);
    await manager().refreshDisplays();
    expect(manager().displays.value, isNotEmpty);

    DVWindowManager.reset();
    expect(manager().displays.value, isEmpty);
    expect(DVWindowManager.displayNames, isEmpty);
  });

  _openWiring();
}

// The hint reaching an actual window.
//
// Resolution is tested in displays_test.dart; what these cover is the wiring:
// that open() passes the resolved display to the platform, and that a hint it
// could not honour is reported on the window rather than swallowed.
void _openWiring() {
  group('opening on a display', () {
    late List<Map<String, Object?>> opens;

    setUp(() {
      opens = <Map<String, Object?>>[];
      DVWindowManager.reset();
      DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
            <String, Object?>{
              'id': 'A',
              'width': 800.0,
              'height': 600.0,
              'name': 'Operator',
              'isPrimary': true,
            },
            <String, Object?>{
              'id': 'B',
              'width': 800.0,
              'height': 600.0,
              'name': 'Customer',
            },
          ]);
      DVNativeBridge.register('window.open', (Object? arguments) {
        opens.add(Map<String, Object?>.from(arguments! as Map));
        return 'native-${opens.length}';
      });
    });

    tearDown(() {
      DVNativeBridge.unregister('window.displays');
      DVNativeBridge.unregister('window.open');
      DVWindowManager.reset();
    });

    test('the resolved display id is handed to the platform', () async {
      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/orders'),
        options: const DVWindowOptions(display: DVDisplayHint.secondary),
      );

      expect(opens.single['displayId'], 'B');
      expect(window.degradation, DVWindowDegradation.none);
    });

    test('a hint enumerates displays when nothing has yet', () async {
      // Otherwise the first window of the process always lands on the primary
      // display, because the list it resolves against is still empty.
      expect(DV.Platform.Window.displays.value, isEmpty);

      await DV.Platform.Window.open(
        const DVRouteTarget('/orders'),
        options: DVWindowOptions(display: DVDisplayHint.byName('Customer')),
      );

      expect(opens.single['displayId'], 'B');
    });

    test('an unhonoured hint opens on no display, and is reported', () async {
      // Not on the primary display. A projector hint that fell back would put
      // the output on the operator's own screen, and it would look like it had
      // worked; letting the OS place the window is the same thing that would
      // have happened with no hint at all.
      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/orders'),
        options: DVWindowOptions(display: DVDisplayHint.byName('Missing')),
      );

      expect(window.degradation, DVWindowDegradation.displayUnavailable);
      expect(opens.single.containsKey('displayId'), isFalse);
      expect(window.presentation, DVWindowPresentation.window,
          reason: 'it still opened');
    });

    test('no hint sends no display id', () async {
      await DV.Platform.Window.open(const DVRouteTarget('/orders'));
      expect(opens.single.containsKey('displayId'), isFalse);
    });

    test('a worse degradation is not overwritten by the display one',
        () async {
      // A window that could not be created at all is the more useful report;
      // "it opened on the wrong screen" would be untrue as well as less
      // severe.
      DVNativeBridge.unregister('window.open');
      DVNativeBridge.register('window.open', (Object? _) => null);

      final DVWindow window = await DV.Platform.Window.open(
        const DVRouteTarget('/orders'),
        options: DVWindowOptions(display: DVDisplayHint.byName('Missing')),
      );

      expect(window.degradation, DVWindowDegradation.platformRefused);
    });
  });
}
