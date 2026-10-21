// DVWindowOptions(takesFocus: false): a projector or stage-display window
// that never takes the keyboard from the operator's window.
//
// The silent failure is the one that matters: a projector that steals focus
// when it opens sends the operator's next keystroke (Space for "take", an
// arrow for the next slide) to a window nobody is looking at. So a platform
// that cannot keep a window from taking focus says so on the window's codes
// (DV-WINDOW-016) rather than opening it as if it had.
import 'package:dartvel_core/dartvel.dart' show DVDiagnostics;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const projectorRoute = DVRouteTarget('/projector');

void main() {
  final List<Map<Object?, Object?>> focusCalls = <Map<Object?, Object?>>[];

  setUp(() {
    DVWindowManager.reset();
    focusCalls.clear();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true,
      sameEngine: true,
      tearOut: true,
    );
    DVNativeBridge.register('window.open', (Object? args) => 'win-1');
    DVNativeBridge.register('window.close', (Object? args) => true);
  });

  tearDown(() {
    DVWindowManager.reset();
    for (final name in <String>['window.open', 'window.close', 'window.setTakesFocus']) {
      DVNativeBridge.unregister(name);
    }
  });

  test('windows take focus unless asked not to', () {
    expect(const DVWindowOptions().takesFocus, isTrue);
  });

  test('takesFocus: false reaches the platform for the window it opened', () async {
    DVNativeBridge.register('window.setTakesFocus', (Object? args) {
      focusCalls.add(args! as Map<Object?, Object?>);
      return true;
    });

    final window = await DV.Platform.window.open(
      projectorRoute,
      options: const DVWindowOptions(takesFocus: false),
    );

    expect(focusCalls.single, <Object?, Object?>{'id': 'win-1', 'takesFocus': false});
    expect(window.codes, isNot(contains('DV-WINDOW-016')));
    expect(window.presentation, DVWindowPresentation.window);
  });

  test('an ordinary window asks nothing about focus', () async {
    DVNativeBridge.register('window.setTakesFocus', (Object? args) {
      focusCalls.add(args! as Map<Object?, Object?>);
      return true;
    });

    await DV.Platform.window.open(projectorRoute);

    expect(focusCalls, isEmpty);
  });

  test('a platform that cannot keep focus away says so (DV-WINDOW-016)', () async {
    DVNativeBridge.register('window.setTakesFocus', (Object? args) => false);

    final window = await DV.Platform.window.open(
      projectorRoute,
      options: const DVWindowOptions(takesFocus: false),
    );

    // Still a window: the request was for a window, and it is one. What it
    // could not promise is said, not hidden.
    expect(window.presentation, DVWindowPresentation.window);
    expect(window.codes, contains('DV-WINDOW-016'));
  });

  test('no binding for it at all is the same as refusing', () async {
    final window = await DV.Platform.window.open(
      projectorRoute,
      options: const DVWindowOptions(takesFocus: false),
    );

    expect(window.codes, contains('DV-WINDOW-016'));
  });

  test('a window that degraded to a page has no focus to keep', () async {
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: false,
      sameEngine: true,
      tearOut: false,
    );

    final window = await DV.Platform.window.open(
      projectorRoute,
      options: const DVWindowOptions(takesFocus: false),
    );

    expect(window.isVirtual, isTrue);
    expect(window.codes, isNot(contains('DV-WINDOW-016')));
  });

  test('DV-WINDOW-016 is a registered diagnostic', () {
    expect(DVDiagnostics.find('DV-WINDOW-016'), isNotNull);
    expect(DVDiagnostics.find('DV-WINDOW-016')!.level, 'warning');
  });
}
