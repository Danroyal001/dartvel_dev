// DVWindowOptions(takesFocus: false) through the desktop bindings: a
// projector window that never takes the keyboard from the operator's window.
//
// On Linux the binding says yes and the surface applies it when the GTK
// window is created (before it is first shown, which is when a window manager
// decides whether to focus it). Elsewhere it says no, and the window carries
// DV-WINDOW-016 rather than quietly taking focus.
import 'dart:io' show Platform;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const projector = DVRouteTarget('/projector');
const stage = DVRouteTarget('/stage');

void main() {
  setUp(() {
    DVWindowManager.reset();
    DVWindowHost.debugResetBindings();
    DVWindowHost.debugRegisterBindings();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true, sameEngine: true, tearOut: true,
    );
  });
  tearDown(() {
    DVWindowManager.reset();
    DVWindowHost.debugResetBindings();
  });

  test('the request a surface is built from says the window takes no focus', () async {
    final window = await DV.Platform.window.open(
      projector,
      options: const DVWindowOptions(takesFocus: false),
    );

    final request = DVWindowHost.debugRequestFor(window.nativeId);
    expect(request, isNotNull);
    if (Platform.isLinux) {
      expect(request!.takesFocus, isFalse);
      expect(window.codes, isNot(contains('DV-WINDOW-016')));
    } else {
      // Not built for Windows or macOS yet: said, not hidden.
      expect(window.codes, contains('DV-WINDOW-016'));
    }
  });

  test('an ordinary window takes focus as before', () async {
    final window = await DV.Platform.window.open(stage);

    expect(DVWindowHost.debugRequestFor(window.nativeId)!.takesFocus, isTrue);
    expect(window.codes, isNot(contains('DV-WINDOW-016')));
  });

  test('a window id the bindings never issued is refused', () async {
    final Object? answer = await DVNativeBridge.invoke<bool>(
      'window.setTakesFocus',
      <String, Object?>{'id': 'dv-window-404', 'takesFocus': false},
    );
    expect(answer, isFalse);
  });
  // Measured on a two-monitor X server: with the OS window refusing focus,
  // the operator's GTK window kept the X input focus, and the keystrokes still
  // reached the projector's widgets. Both windows are one widget tree with one
  // FocusManager, and keys go to its primary focus whichever OS window
  // delivered them, so an `autofocus` in the projector's route took them. A
  // window that takes no focus has to take none inside Flutter too.
  testWidgets('nothing in a window that takes no focus can take the keyboard', (WidgetTester tester) async {
    final window = await DV.Platform.window.open(
      projector,
      options: const DVWindowOptions(takesFocus: false),
    );
    final FocusNode operatorNode = FocusNode(debugLabel: 'operator');
    final FocusNode projectorNode = FocusNode(debugLabel: 'projector');
    addTearDown(operatorNode.dispose);
    addTearDown(projectorNode.dispose);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: <Widget>[
        Focus(focusNode: operatorNode, autofocus: true, child: const SizedBox(height: 10)),
        DVWindowHost.debugContentFor(
          window,
          Focus(focusNode: projectorNode, autofocus: true, child: const SizedBox(height: 10)),
        ),
      ]),
    ));
    await tester.pump();
    projectorNode.requestFocus();
    await tester.pump();

    expect(projectorNode.hasFocus, isFalse);
    expect(operatorNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('an ordinary window\'s content is left as it is', (WidgetTester tester) async {
    final window = await DV.Platform.window.open(stage);
    const Widget child = SizedBox(key: Key('content'));
    expect(identical(DVWindowHost.debugContentFor(window, child), child), isTrue);
  });
}
