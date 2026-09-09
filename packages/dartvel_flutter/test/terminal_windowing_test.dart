// What DV.Window.open() does when the frames are landing in a terminal.
//
// The specification is explicit: in a terminal open() navigates. The route is
// presented as a page, with DVWindowPresentation.page and
// DVWindowDegradation.capabilityUnsupported (DV-WINDOW-001), exactly as it
// does on a phone, and application code reads the presentation it got rather
// than branching on whether it is in a terminal.
//
// Capability detection knew about desktops, the web, Android and iPad and had
// never heard of the render surface, so a terminal build with a window
// binding registered would have asked the operating system for a second
// window -- from a process whose entire reason to exist is that there is no
// window server to ask. The obvious idea of spawning a second terminal
// emulator fails for the same reason.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const orders = DVRouteTarget('/orders');

void main() {
  setUp(DVWindowManager.reset);
  tearDown(() {
    DVWindowManager.reset();
    DV.Platform.useRenderSurface(null);
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
  });

  void renderInTerminal() {
    DV.Platform.useRenderSurface(
      DVRenderSurface.terminal,
      terminal: DVTerminalSurface.fixed(
        columns: 120,
        rows: 40,
        graphics: DVTerminalGraphics.ansi,
      ),
    );
  }

  test('a terminal has no second window, whatever the platform says', () {
    final DVWindowingCapability terminal = DVWindowingCapability.detect(
      isDesktop: true,
      isWeb: false,
      isAndroid: false,
      isTablet: false,
      isIOS: false,
      hasNativeWindowBinding: true,
      isTerminal: true,
    );
    expect(terminal.multiWindow, isFalse);
    expect(terminal.tearOut, isFalse);
    expect(terminal.ownedWindows, isFalse);
    expect(terminal.inPageViews, isFalse);
  });

  test('open() navigates in a terminal and says why', () async {
    // The binding is registered and would answer: this asserts the terminal
    // is what stops the call, not the absence of an integration.
    DVNativeBridge.register('window.open', (Object? args) => 'win-1');
    DVNativeBridge.register('window.close', (Object? args) => true);
    renderInTerminal();

    final DVWindow window = await DV.Platform.Window.open(orders);

    expect(window.presentation, DVWindowPresentation.page);
    expect(window.degradation, DVWindowDegradation.capabilityUnsupported);
    expect(window.codes, contains('DV-WINDOW-001'));
    expect(window.route.path, '/orders');
    expect(window.isVirtual, isTrue);
  });

  test('the same call opens a real window once the surface is a GUI', () async {
    // The control. Without it the first test passes on any build where the
    // window binding is simply missing, which is every test binary, and would
    // have proved nothing about the terminal at all.
    DVNativeBridge.register('window.open', (Object? args) => 'win-1');
    DVNativeBridge.register('window.close', (Object? args) => true);
    DV.Platform.useRenderSurface(DVRenderSurface.gui);

    final DVWindow window = await DV.Platform.Window.open(orders);

    expect(window.presentation, DVWindowPresentation.window);
    expect(window.degradation, DVWindowDegradation.none);
  });

  test('a terminal offers no move-to-display, however many are attached', () {
    // withDisplayCount recomputes displays from the live list, and a terminal
    // build can still enumerate the monitors plugged into the machine it runs
    // on. A workspace reads this to decide whether to show a "move to
    // display" control, and there is nowhere for it to move anything to.
    renderInTerminal();
    final DVWindowingCapability terminal = DVWindowingCapability.detect(
      isDesktop: true,
      isWeb: false,
      isAndroid: false,
      isTablet: false,
      isIOS: false,
      hasNativeWindowBinding: true,
      isTerminal: true,
    ).withDisplayCount(3);
    expect(terminal.displays, isFalse);
    expect(terminal.displayKiosk, isFalse);
  });
}
