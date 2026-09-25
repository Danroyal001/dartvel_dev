import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start devices-platform
// One surface on every target. A feature the platform does not have answers
// that it is unavailable, and does not throw, so a call site does not need
// to know which platform it is on.
Future<void> shareReceipt(String orderId) async {
  await DV.Haptics.lightVibrate();
  await DV.Share.shareText('Order $orderId is on its way.');
}
// docs:end

// docs:start devices-home-widget
// A widget, with the annotation on it. The same functional widget every
// other piece of Dartvel UI is: the input is private, and the generated
// NextShiftWidget is what the home screen and the route reach.
@DVHomeWidget(title: 'Next shift')
@DVFunctionalWidget()
Widget _nextShiftWidget(BuildContext context) => const DVBox.list(<Widget>[
      DVText('Next shift'),
      DVText('Thursday, 07:00'),
    ]);

// What the home screen shows, pushed from anywhere in the app.
Future<void> refreshShift(String when) =>
    DVHomeWidgets.publish('next-shift', when);
// docs:end

// docs:start devices-window
// Idempotent by route: opening a route a window already shows returns that
// window instead of a second copy of it.
// The route is the generated target, never a string: moving the page moves
// this with it, and a route that no longer exists is a compile error rather
// than a window onto nothing.
Future<DVWindow> openCart() => DV.Platform.Window.open(DVRoutes.cart);
// docs:end

// docs:start devices-foldable
// The fold is a rectangle the page is told about, so a layout can keep
// content out from under the hinge without guessing at a breakpoint.
Widget shiftBoard(BuildContext context) {
  final List<DVFold> folds = context.screen.folds;
  final bool split = folds.any((DVFold fold) => fold.occludes);
  return DVBox.list(<Widget>[
    const DVText('Today'),
    if (!split) const DVText('Tomorrow'),
  ]);
}
// docs:end

// docs:start devices-desktop
// Trays, menus and shortcuts are the same DV.Platform surface, so a desktop
// build asks for them and a phone build answers that it has none.
Future<void> installDesktopChrome() async {
  await DV.Platform.Tray.show(
    icon: DVAsset.tray,
    tooltip: 'Oakline',
    menu: const <DVTrayMenuItem>[
      DVTrayMenuItem(id: 'cart', label: 'Open the cart'),
    ],
    onSelected: (String id) => DV.Platform.Window.open(DVRoutes.cart),
  );
  await DV.Platform.Shortcuts.register(
    const DVGlobalShortcut(id: 'cart', accelerator: 'Ctrl+Shift+O'),
    onPressed: () => DV.Platform.Window.open(DVRoutes.cart),
  );
}
// docs:end
