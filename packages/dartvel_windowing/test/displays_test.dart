// Which display a window goes to.
//
// The spec fixes the binding name (`window.displays`) and the shape of a
// display, and says placement is *which display, never where on it*. These
// tests cover the part that is pure logic: turning what the platform reports
// into displays, and resolving a hint against them. The X11 enumeration itself
// is verified by running the application, because a headless test has no
// display server to ask.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two displays side by side, the left one primary — an operator laptop with a
/// projector plugged in.
const twoDisplays = <Map<String, Object?>>[
  <String, Object?>{
    'id': 'x11-0',
    'name': 'eDP-1',
    'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 800.0,
    'devicePixelRatio': 1.0,
    'isPrimary': true,
  },
  <String, Object?>{
    'id': 'x11-1',
    'name': 'HDMI-1',
    'x': 1280.0, 'y': 0.0, 'width': 1920.0, 'height': 1080.0,
    'devicePixelRatio': 1.0,
    'isPrimary': false,
  },
];

void main() {
  group('reading what the platform reports', () {
    test('turns the reported rows into displays', () {
      final displays = DVDisplays.fromBinding(twoDisplays);

      expect(displays, hasLength(2));
      expect(displays.first.name, 'eDP-1');
      expect(displays.first.isPrimary, isTrue);
      expect(displays.last.bounds, const Rect.fromLTWH(1280, 0, 1920, 1080));
      expect(displays.last.isPrimary, isFalse);
    });

    test('a row missing its bounds is dropped, not defaulted to zero', () {
      // A display at 0x0 would be picked as a projector target and then show
      // nothing, which is worse than not offering it.
      final displays = DVDisplays.fromBinding(<Map<String, Object?>>[
        twoDisplays.first,
        <String, Object?>{'id': 'x11-9', 'name': 'broken'},
      ]);

      expect(displays.map((d) => d.id), <String>['x11-0']);
    });

    test('reports no primary rather than inventing one', () {
      final displays = DVDisplays.fromBinding(<Map<String, Object?>>[
        <String, Object?>{...twoDisplays.last},
      ]);

      expect(displays.single.isPrimary, isFalse);
    });
  });

  group('the binding', () {
    tearDown(DVWindowHost.debugResetBindings);

    test('registering makes window.displays answerable', () async {
      DVWindowHost.debugRegisterBindings();
      expect(DVNativeBridge.isRegistered('window.displays'), isTrue);
    });

    test('answers empty where there is no window system, rather than throwing',
        () async {
      // A CI runner with no X server is not a fault. An application that
      // wanted a projector learns that from an empty list, which is the same
      // path as an unplugged cable.
      DVWindowHost.debugRegisterBindings();
      await expectLater(DVDisplays.query(), completion(isEmpty));
    });

    test('answers empty when nothing is registered at all', () async {
      await expectLater(DVDisplays.query(), completion(isEmpty));
    });
  });

  group('resolving a hint', () {
    late List<DVDisplay> displays;
    setUp(() => displays = DVDisplays.fromBinding(twoDisplays));

    test('primary picks the primary display', () {
      expect(DVDisplayHint.primary.resolve(displays)?.name, 'eDP-1');
    });

    test('secondary picks the first non-primary, which is the projector', () {
      expect(DVDisplayHint.secondary.resolve(displays)?.name, 'HDMI-1');
    });

    test('byName matches the display the device profile named', () {
      expect(const DVDisplayHint.byName('HDMI-1').resolve(displays)?.id, 'x11-1');
    });

    test('byIndex uses OS order', () {
      expect(const DVDisplayHint.byIndex(1).resolve(displays)?.name, 'HDMI-1');
    });

    test('byId matches the stable id', () {
      expect(const DVDisplayHint.byId('x11-0').resolve(displays)?.name, 'eDP-1');
    });

    test('a hint that matches nothing resolves to null, and does not fall back',
        () {
      // Falling back to the primary would put the lyrics on the operator's
      // laptop in front of the congregation. The caller decides what to do
      // when the projector is unplugged.
      expect(const DVDisplayHint.byName('Customer').resolve(displays), isNull);
      expect(const DVDisplayHint.byIndex(7).resolve(displays), isNull);
    });

    test('secondary resolves to null when nothing is designated primary', () {
      // Found by running it: an X server that designates no primary made
      // "first non-primary" mean "the first display", so the projector hint
      // resolved to the operator's own screen. When nothing is primary,
      // secondary is not a meaningful question and must not be answered.
      final undesignated = DVDisplays.fromBinding(
        twoDisplays
            .map((d) => <String, Object?>{...d, 'isPrimary': false})
            .toList(),
      );

      expect(undesignated, hasLength(2));
      expect(DVDisplayHint.secondary.resolve(undesignated), isNull);
    });

    test('secondary resolves to null on a single-display machine', () {
      final single = DVDisplays.fromBinding(<Map<String, Object?>>[
        twoDisplays.first,
      ]);
      expect(DVDisplayHint.secondary.resolve(single), isNull);
    });
  });
}
