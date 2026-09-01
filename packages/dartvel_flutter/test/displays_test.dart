// Display enumeration and DVDisplayHint resolution.
//
// The contract gives `DV.Window.displays` and lets a window ask for a display
// by hint -- `DVDisplayHint.byName('Customer')` is the kiosk case, from a
// device profile. Nothing enumerated displays, so every hint had nothing to
// resolve against and `capability.displays` described a surface with no
// implementation.
//
// The failures worth testing are the quiet ones. A hint that cannot be honoured
// must not silently place a customer-facing kiosk window on the operator's
// screen with no diagnostic, and a display list decoded from a native payload
// must not invent geometry it was not given.
import 'dart:ui' show Rect, Size;

import 'package:dartvel_flutter/src/windowing/displays.dart';
import 'package:dartvel_flutter/src/windowing/window.dart';
import 'package:flutter_test/flutter_test.dart';

/// One display as a native payload entry.
Map<String, Object?> raw({
  String id = '1',
  double dpr = 1.0,
  double width = 1920,
  double height = 1080,
  double refreshRate = 60,
  String? name,
  bool? isPrimary,
  double? left,
  double? top,
}) =>
    <String, Object?>{
      'id': id,
      'devicePixelRatio': dpr,
      'width': width,
      'height': height,
      'refreshRate': refreshRate,
      if (name != null) 'name': name,
      if (isPrimary != null) 'isPrimary': isPrimary,
      if (left != null) 'left': left,
      if (top != null) 'top': top,
    };

void main() {
  group('decoding a display payload', () {
    test('it reads the fields a platform reports', () {
      final List<DVDisplay> displays = DVDisplays.decode(<Object?>[
        raw(id: '7', dpr: 2.0, width: 2560, height: 1440, name: 'Studio'),
      ]);

      expect(displays, hasLength(1));
      expect(displays.single.id, '7');
      expect(displays.single.name, 'Studio');
      expect(displays.single.devicePixelRatio, 2.0);
      expect(displays.single.refreshRate, 60);
    });

    test('bounds are logical pixels, not physical', () {
      // The contract says logical. A 2560x1440 panel at dpr 2 is a 1280x720
      // surface to lay out in, and reporting the physical number would make
      // every "is this a big screen" decision wrong by the pixel ratio.
      final DVDisplay display = DVDisplays.decode(<Object?>[
        raw(dpr: 2.0, width: 2560, height: 1440),
      ]).single;

      expect(display.bounds.width, 1280);
      expect(display.bounds.height, 720);
    });

    test('a reported layout origin is kept, and marked known', () {
      final DVDisplay display = DVDisplays.decode(<Object?>[
        raw(dpr: 1.0, width: 1920, height: 1080, left: 1920, top: 0),
      ]).single;

      expect(display.bounds, const Rect.fromLTWH(1920, 0, 1920, 1080));
      expect(display.hasLayout, isTrue);
    });

    test('an unreported origin is not invented', () {
      // Flutter's own PlatformDispatcher.displays carries size and pixel ratio
      // but no layout origin. Defaulting both displays to (0,0) would make two
      // monitors claim the same rectangle -- a plausible-looking answer that is
      // wrong, which is worse than one that says it does not know.
      final List<DVDisplay> displays = DVDisplays.decode(<Object?>[
        raw(id: '1'),
        raw(id: '2'),
      ]);

      expect(displays.every((DVDisplay d) => !d.hasLayout), isTrue,
          reason: 'no origin was reported');
      expect(displays.first.bounds.size, const Size(1920, 1080),
          reason: 'the size is still real');
    });

    test('the first display is primary when nothing says otherwise', () {
      final List<DVDisplay> displays =
          DVDisplays.decode(<Object?>[raw(id: '1'), raw(id: '2')]);

      expect(displays.first.isPrimary, isTrue);
      expect(displays.last.isPrimary, isFalse);
    });

    test('a platform-reported primary wins over ordering', () {
      final List<DVDisplay> displays = DVDisplays.decode(<Object?>[
        raw(id: '1', isPrimary: false),
        raw(id: '2', isPrimary: true),
      ]);

      expect(displays.first.isPrimary, isFalse);
      expect(displays.last.isPrimary, isTrue);
    });

    test('exactly one display is primary even if the platform says two are',
        () {
      // Two primaries would make DVDisplayHint.primary ambiguous and its
      // result depend on iteration order.
      final List<DVDisplay> displays = DVDisplays.decode(<Object?>[
        raw(id: '1', isPrimary: true),
        raw(id: '2', isPrimary: true),
      ]);

      expect(displays.where((DVDisplay d) => d.isPrimary), hasLength(1));
    });

    test('a device profile names a display over the OS name', () {
      // Kiosk deployments address displays by role, and the OS name is
      // whatever the panel's EDID says.
      final List<DVDisplay> displays = DVDisplays.decode(
        <Object?>[raw(id: '2', name: 'DELL U2412M')],
        profileNames: <String, String>{'2': 'Customer'},
      );

      expect(displays.single.name, 'Customer');
    });

    test('a display with no name gets a stable derived one', () {
      // Never empty: the name reaches logs and `dartvel explain`.
      final DVDisplay display = DVDisplays.decode(<Object?>[raw(id: '3')]).single;
      expect(display.name, isNotEmpty);
    });

    test('a malformed payload yields no displays rather than throwing', () {
      // It arrives from a native binding, so it is not trusted input.
      expect(DVDisplays.decode('not a list'), isEmpty);
      expect(DVDisplays.decode(null), isEmpty);
      expect(DVDisplays.decode(<Object?>['nonsense', 42]), isEmpty);
    });

    test('an entry missing its size is dropped, not defaulted to zero', () {
      // A 0x0 display would satisfy every hint and place a window nowhere.
      final List<DVDisplay> displays = DVDisplays.decode(<Object?>[
        <String, Object?>{'id': '1'},
        raw(id: '2'),
      ]);

      expect(displays.map((DVDisplay d) => d.id), <String>['2']);
    });

    test('a non-positive pixel ratio falls back to 1 rather than dividing', () {
      final DVDisplay display =
          DVDisplays.decode(<Object?>[raw(dpr: 0, width: 800, height: 600)])
              .single;
      expect(display.bounds.size, const Size(800, 600));
    });
  });

  group('resolving a hint', () {
    final List<DVDisplay> three = DVDisplays.decode(<Object?>[
      raw(id: '1', name: 'Operator', isPrimary: true),
      raw(id: '2', name: 'Customer'),
      raw(id: '3', name: 'Signage'),
    ]);

    test('no hint resolves to the primary display', () {
      final DVDisplayResolution result = DVDisplays.resolve(three, null);
      expect(result.display?.id, '1');
      expect(result.exact, isTrue);
      expect(result.degradation, DVWindowDegradation.none);
    });

    test('primary resolves to the primary display', () {
      expect(DVDisplays.resolve(three, DVDisplayHint.primary).display?.id, '1');
    });

    test('secondary is the first display that is not primary', () {
      expect(
          DVDisplays.resolve(three, DVDisplayHint.secondary).display?.id, '2');
    });

    test('secondary on a single-display machine falls back and says so', () {
      final List<DVDisplay> one = DVDisplays.decode(<Object?>[raw(id: '1')]);
      final DVDisplayResolution result =
          DVDisplays.resolve(one, DVDisplayHint.secondary);

      expect(result.display?.id, '1');
      expect(result.exact, isFalse);
      expect(result.degradation, DVWindowDegradation.displayUnavailable);
    });

    test('byIndex addresses displays in reported order', () {
      expect(DVDisplays.resolve(three, DVDisplayHint.byIndex(2)).display?.id,
          '3');
    });

    test('byIndex past the end falls back to primary and says so', () {
      final DVDisplayResolution result =
          DVDisplays.resolve(three, DVDisplayHint.byIndex(9));
      expect(result.display?.id, '1');
      expect(result.exact, isFalse);
      expect(result.degradation, DVWindowDegradation.displayUnavailable);
    });

    test('a negative index does not wrap or throw', () {
      final DVDisplayResolution result =
          DVDisplays.resolve(three, DVDisplayHint.byIndex(-1));
      expect(result.display?.id, '1');
      expect(result.exact, isFalse);
    });

    test('byId finds the display', () {
      expect(DVDisplays.resolve(three, DVDisplayHint.byId('3')).display?.id,
          '3');
    });

    test('byName finds the display', () {
      expect(
          DVDisplays.resolve(three, DVDisplayHint.byName('Customer')).display?.id,
          '2');
    });

    test('an unplugged named display degrades rather than silently relocating',
        () {
      // The kiosk case. A customer-facing window quietly appearing on the
      // operator's screen with no diagnostic is the failure this exists to
      // make visible.
      final DVDisplayResolution result =
          DVDisplays.resolve(three, DVDisplayHint.byName('Customer2'));

      expect(result.display?.id, '1', reason: 'it still opens somewhere');
      expect(result.exact, isFalse);
      expect(result.degradation, DVWindowDegradation.displayUnavailable);
    });

    test('with no displays at all it resolves to nothing, not a crash', () {
      final DVDisplayResolution result =
          DVDisplays.resolve(const <DVDisplay>[], DVDisplayHint.primary);
      expect(result.display, isNull);
      expect(result.degradation, DVWindowDegradation.displayUnavailable);
    });
  });

  group('the diagnostic code', () {
    test('displayUnavailable has a stable code and is developer-actionable',
        () {
      expect(DVWindowDegradation.displayUnavailable.code, 'DV-WINDOW-006');
      expect(DVWindowDegradation.displayUnavailable.level, 'warning');
      expect(DVWindowDegradation.displayUnavailable.reason, isNotEmpty);
    });

    test('every degradation code is unique', () {
      // Two degradations sharing a code would make `dartvel explain` answer
      // the wrong question.
      final List<String> codes = <String>[
        for (final DVWindowDegradation d in DVWindowDegradation.values)
          if (d.code != null) d.code!,
      ];
      expect(codes.toSet(), hasLength(codes.length));
    });
  });
}
