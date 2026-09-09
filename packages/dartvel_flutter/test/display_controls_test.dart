// DV.Platform.display: what the four calls in the Platform section actually
// reach on a device.
//
// enableKiosk() and disableKiosk() went straight to display.enableKiosk and
// display.disableKiosk, which nothing registers on any target, so both threw
// everywhere -- while kiosk.enforce and kiosk.release, the bindings that hold
// a real kiosk, sat registered and unused on Linux, Windows, macOS, Android
// and the web. DVKioskOptions went the same way: every field was serialised
// into a map handed to a binding that did not exist, so allowedExitKeys named
// keys nothing ever let through.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const List<String> displayBindings = <String>[
    'display.enterFullscreen',
    'display.exitFullscreen',
    'display.enableKiosk',
    'display.disableKiosk',
  ];
  const List<String> kioskBindings = <String>['kiosk.enforce', 'kiosk.release'];

  Object? enforceArguments;
  int releases = 0;

  /// What Linux, Windows, macOS, Android and the web register today: the
  /// kiosk layer, and no display.* binding at all.
  void registerKioskBindingsOnly() {
    enforceArguments = null;
    releases = 0;
    DVNativeBridge.register('kiosk.enforce', (Object? arguments) {
      enforceArguments = arguments;
      return <String, Object?>{
        'blocked': <String>['Alt+tab'],
        'fullscreen': true,
      };
    });
    DVNativeBridge.register('kiosk.release', (Object? _) {
      releases++;
      return true;
    });
  }

  List<String> combosSent() {
    final Map<Object?, Object?> map = enforceArguments as Map<Object?, Object?>;
    return <String>[for (final Object? c in map['combos'] as List) '$c'];
  }

  setUp(() {
    for (final String name in <String>[...displayBindings, ...kioskBindings]) {
      DVNativeBridge.unregister(name);
    }
    enforceArguments = null;
    releases = 0;
  });

  tearDown(() async {
    // The flags are static and survive the test, so a kiosk left on would
    // make the next test's assertion pass for the wrong reason.
    registerKioskBindingsOnly();
    await DV.Platform.display.disableKiosk();
    for (final String name in <String>[...displayBindings, ...kioskBindings]) {
      DVNativeBridge.unregister(name);
    }
  });

  test('enableKiosk holds the kiosk through the binding the platform has', () async {
    registerKioskBindingsOnly();

    await DV.Platform.display.enableKiosk();

    expect(enforceArguments, isNotNull,
        reason: 'kiosk.enforce is what actually holds a kiosk on every '
            'platform that can hold one; enableKiosk must reach it rather '
            'than throw on a display.* name nothing registers');
    expect(combosSent(), contains('Alt+tab'));
    expect(DV.Platform.display.isKiosk, isTrue);
  });

  test('allowedExitKeys leaves those combos ungrabbed', () async {
    registerKioskBindingsOnly();

    await DV.Platform.display.enableKiosk(
      const DVKioskOptions(allowedExitKeys: <String>['Alt+F4']),
    );

    expect(combosSent(), isNot(contains('Alt+f4')),
        reason: 'a key the caller listed as an exit must not be grabbed, or '
            'the option is decoration');
    expect(combosSent(), contains('Alt+tab'),
        reason: 'exempting one combo must not exempt the rest');
  });

  test('the fullscreen option reaches the enforcement', () async {
    registerKioskBindingsOnly();

    await DV.Platform.display.enableKiosk(
      const DVKioskOptions(fullscreen: false),
    );

    final Map<Object?, Object?> map = enforceArguments as Map<Object?, Object?>;
    expect(map['fullscreen'], isFalse);
  });

  test('disableKiosk lets go through the same layer', () async {
    registerKioskBindingsOnly();
    await DV.Platform.display.enableKiosk();

    await DV.Platform.display.disableKiosk();

    expect(releases, 1);
    expect(DV.Platform.display.isKiosk, isFalse);
  });

  test('a dedicated display.enableKiosk binding is preferred', () async {
    registerKioskBindingsOnly();
    Object? dedicated;
    DVNativeBridge.register('display.enableKiosk', (Object? arguments) {
      dedicated = arguments;
      return true;
    });

    await DV.Platform.display.enableKiosk();

    expect(dedicated, isNotNull);
    expect(enforceArguments, isNull,
        reason: 'a platform that binds the name itself owns the behaviour; '
            'the kiosk layer is the fallback, not an extra call');
  });

  test('with no kiosk binding at all it still says which name is missing', () async {
    await expectLater(
      DV.Platform.display.enableKiosk(),
      throwsA(isA<StateError>().having(
        (StateError e) => e.message,
        'message',
        contains('display.enableKiosk'),
      )),
    );
  });
}
