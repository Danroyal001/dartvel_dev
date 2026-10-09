// DVWindow.setFullscreen: a projector output fills the display it was sent to.
//
// The silent failure here is the one that matters: fullscreen on the wrong
// display puts the output on the operator's own screen, in front of the room,
// and looks like it worked. So a display hint that matches nothing is refused,
// never "fullscreen wherever the window is".
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const projectorRoute = DVRouteTarget('/projector');

void main() {
  final List<Map<Object?, Object?>> calls = <Map<Object?, Object?>>[];

  setUp(() {
    DVWindowManager.reset();
    calls.clear();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true,
      sameEngine: true,
      tearOut: true,
    );
    DVNativeBridge.register('window.open', (Object? args) => 'win-1');
    DVNativeBridge.register('window.close', (Object? args) => true);
    DVNativeBridge.register('window.displays', (Object? _) => <Map<String, Object?>>[
          <String, Object?>{'id': 'laptop', 'name': 'eDP-1', 'x': 0.0, 'y': 0.0,
            'width': 1920.0, 'height': 1080.0, 'devicePixelRatio': 1.0, 'isPrimary': true},
          <String, Object?>{'id': 'wall', 'name': 'HDMI-1', 'x': 1920.0, 'y': 0.0,
            'width': 1920.0, 'height': 1080.0, 'devicePixelRatio': 1.0, 'isPrimary': false},
        ]);
    DVNativeBridge.register('window.setFullscreen', (Object? args) {
      calls.add(args! as Map<Object?, Object?>);
      return true;
    });
  });

  tearDown(() {
    DVWindowManager.reset();
    for (final name in <String>['window.open', 'window.close', 'window.displays', 'window.setFullscreen']) {
      DVNativeBridge.unregister(name);
    }
  });

  test('fullscreens on the display the hint names, by id', () async {
    final window = await DV.Platform.window.open(projectorRoute);

    final ok = await window.setFullscreen(true, on: DVDisplayHint.secondary);

    expect(ok, isTrue);
    expect(calls.single, <Object?, Object?>{'id': 'win-1', 'fullscreen': true, 'displayId': 'wall'});
    expect(window.lifecycle.value, DVWindowLifecycle.fullscreen);
  });

  test('a hint that matches no display is refused, not fullscreened anywhere', () async {
    final window = await DV.Platform.window.open(projectorRoute);

    final ok = await window.setFullscreen(true, on: DVDisplayHint.byName('HDMI-9'));

    expect(ok, isFalse);
    expect(calls, isEmpty);
    expect(window.lifecycle.value, isNot(DVWindowLifecycle.fullscreen));
  });

  test('leaving fullscreen names no display', () async {
    final window = await DV.Platform.window.open(projectorRoute);
    await window.setFullscreen(true, on: DVDisplayHint.secondary);

    final ok = await window.setFullscreen(false);

    expect(ok, isTrue);
    expect(calls.last, <Object?, Object?>{'id': 'win-1', 'fullscreen': false});
    expect(window.lifecycle.value, DVWindowLifecycle.active);
  });

  test('a platform without the binding answers false rather than throwing', () async {
    DVNativeBridge.unregister('window.setFullscreen');
    final window = await DV.Platform.window.open(projectorRoute);

    expect(await window.setFullscreen(true), isFalse);
  });

  test('a virtual window answers false', () async {
    DVWindowManager.capabilityOverride = const DVWindowingCapability();
    final window = await DV.Platform.window.open(projectorRoute);
    expect(window.isVirtual, isTrue);

    expect(await window.setFullscreen(true), isFalse);
    expect(calls, isEmpty);
  });
}
