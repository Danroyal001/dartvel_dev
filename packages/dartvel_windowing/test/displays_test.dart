// Which display a window goes to, from this package's side of the seam.
//
// The display type, the payload decoder and hint resolution live in
// dartvel_flutter, because an application needs them whether or not it takes
// this package. What is this package's own is the `window.displays` binding
// and the X11 enumeration behind it, so what these cover is the seam: that the
// rows the binding answers with are rows the shared decoder accepts, and that
// nothing is lost crossing it.
//
// The X11 enumeration itself is verified by running the application, because a
// headless test has no display server to ask.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two displays side by side, the left one primary — an operator laptop with a
/// projector plugged in. Written in the key spelling the X11 enumeration uses.
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the rows this package answers with', () {
    test('are rows the shared decoder accepts', () {
      // The seam. If the enumeration and the decoder disagreed about a key,
      // every display would be dropped and the failure would look like "no
      // second display" rather than like a mismatch.
      final List<DVDisplay> displays = DVDisplays.decode(twoDisplays);

      expect(displays, hasLength(2));
      expect(displays.map((DVDisplay d) => d.name), <String>['eDP-1', 'HDMI-1']);
      expect(displays.map((DVDisplay d) => d.id), <String>['x11-0', 'x11-1']);
    });

    test('keep the geometry XRandR reported', () {
      // 'x'/'y' is this enumeration's spelling. Losing it would put both
      // displays at the same origin.
      final List<DVDisplay> displays = DVDisplays.decode(twoDisplays);

      expect(displays.last.bounds.left, 1280);
      expect(displays.last.bounds.width, 1920);
      expect(displays.last.hasLayout, isTrue);
    });

    test('keep which display XRandR called primary', () {
      // The whole projector case rests on this: secondary is only meaningful
      // once something is primary.
      final List<DVDisplay> displays = DVDisplays.decode(twoDisplays);

      expect(displays.first.isPrimary, isTrue);
      expect(displays.last.isPrimary, isFalse);
      expect(DVDisplays.resolve(displays, DVDisplayHint.secondary).display?.name,
          'HDMI-1');
    });

    test('a Xinerama answer designates no primary, and secondary says so', () {
      // Xinerama reports no primary at all. Every row is nominally
      // non-primary, so answering "the first non-primary" would hand back the
      // operator's own screen -- which is what a real X server caught.
      final List<DVDisplay> displays = DVDisplays.decode(<Map<String, Object?>>[
        for (final Map<String, Object?> row in twoDisplays)
          <String, Object?>{...row, 'isPrimary': false},
      ]);

      expect(displays.any((DVDisplay d) => d.isPrimary), isFalse);
      expect(DVDisplays.resolve(displays, DVDisplayHint.secondary).display,
          isNull);
    });
  });

  group('the binding', () {
    tearDown(DVWindowHost.debugResetBindings);

    test('registering makes window.displays answerable', () {
      DVWindowHost.debugRegisterBindings();
      expect(DVNativeBridge.isRegistered('window.displays'), isTrue);
    });

    test('answers a list where there is no window system, rather than throwing',
        () async {
      // A CI runner with no X server is not a fault. An application that
      // wanted a projector learns that from an empty list, which is the same
      // path as an unplugged cable.
      DVWindowHost.debugRegisterBindings();

      final Object? answered =
          await DVNativeBridge.invoke<Object?>('window.displays');
      expect(answered, isA<List<Object?>>());
      expect(DVDisplays.decode(answered), isA<List<DVDisplay>>());
    });

    test('an unregistered binding leaves enumeration to Flutter', () async {
      // DV.Platform.Window.refreshDisplays falls back to
      // PlatformDispatcher.displays, so not registering costs the OS-only
      // fields, not the display list.
      expect(DVNativeBridge.isRegistered('window.displays'), isFalse);

      final List<DVDisplay> displays =
          await DV.Platform.Window.refreshDisplays();
      expect(displays, isNotEmpty);
      expect(displays.first.hasLayout, isFalse,
          reason: 'Flutter reports no layout origin');
    });
  });
}
