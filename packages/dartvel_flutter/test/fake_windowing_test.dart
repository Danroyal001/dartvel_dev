// DV.Test.fakeWindowing, the explicit windowing fake.
//
// The specification's rule is "fakes are explicit; no test passes because
// windowing was silently absent". Without a fake, a test asserting that a
// route presents as a page passes on a CI runner for the wrong reason -- not
// because the code degrades correctly, but because nothing registered
// window.open and the capability was false anyway. The same test would have
// passed with the degradation logic deleted.
//
// So the fake is named, and the capability it installs is stated at the call
// site rather than inherited from whatever the host happens to be.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(DVWindowManager.reset);

  group('faking a capability', () {
    test('a phone has no windows, and open presents the route in place',
        () async {
      DV.Test.fakeWindowing(const DVWindowingCapability());

      final DVWindow window =
          await DV.Platform.Window.open(const DVRouteTarget('/orders'));

      expect(window.presentation, DVWindowPresentation.page);
      expect(window.degradation, DVWindowDegradation.capabilityUnsupported);
    });

    test('a desktop capability is a named thing, not a literal', () {
      // Four booleans at a call site say nothing about what target they
      // describe, and the combination that means "desktop" is not obvious.
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());

      final DVWindowingCapability capability = DV.Platform.Window.capability;
      expect(capability.multiWindow, isTrue);
      expect(capability.sameEngine, isTrue);
      expect(capability.tearOut, isTrue);
    });

    test('the fake replaces detection rather than merging with it', () {
      DV.Test.fakeWindowing(const DVWindowingCapability(multiWindow: true));

      final DVWindowingCapability capability = DV.Platform.Window.capability;
      expect(capability.multiWindow, isTrue);
      expect(capability.sameEngine, isFalse,
          reason: 'nothing was asked for beyond multiWindow');
    });

    test('capability.displays still tracks the real display list', () async {
      // It is the one capability that changes while the process runs, so it is
      // read from the display list rather than frozen into the fake -- a fake
      // that froze it would make a "move to display" control untestable.
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      expect(DV.Platform.Window.capability.displays, isFalse);

      DVNativeBridge.register('window.displays', (Object? _) => <Object?>[
            <String, Object?>{'id': 'A', 'width': 800.0, 'height': 600.0},
            <String, Object?>{'id': 'B', 'width': 800.0, 'height': 600.0},
          ]);
      addTearDown(() => DVNativeBridge.unregister('window.displays'));
      await DV.Platform.Window.refreshDisplays();

      expect(DV.Platform.Window.capability.displays, isTrue);
    });
  });

  group('clearing it', () {
    // tearOut is the discriminator rather than multiWindow: the test host
    // reports as Android, whose detection already gives multiWindow true, so
    // asserting on that would pass whether or not the override was cleared.
    test('reset puts detection back', () {
      DV.Test.fakeWindowing(DVWindowingCapability.desktop());
      expect(DV.Platform.Window.capability.tearOut, isTrue);

      DVWindowManager.reset();

      expect(DV.Platform.Window.capability.tearOut, isFalse,
          reason: 'detection, not the fake');
    });

    test('a fake does not leak into the next test', () {
      // The reason reset is in tearDown above: a capability that survived
      // would make the next test pass or fail on the previous one's setup.
      expect(DV.Platform.Window.capability.tearOut, isFalse);
    });
  });
}
