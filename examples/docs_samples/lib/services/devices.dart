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
Future<DVWindow> openCart() => DV.Platform.window.open(DVRoutes.cart);
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
  await DV.Platform.tray.show(
    icon: DVAsset.tray,
    tooltip: 'Oakline',
    menu: const <DVTrayMenuItem>[
      DVTrayMenuItem.header('Oakline'),
      DVTrayMenuItem.separator(),
      DVTrayMenuItem(id: 'cart', label: 'Open the cart'),
      DVTrayMenuItem(id: 'sounds', label: 'Order sounds', checked: true),
    ],
    onSelected: (String id) => DV.Platform.window.open(DVRoutes.cart),
  );
  // The same icon, changed in place: no flicker, no second icon.
  await DV.Platform.tray.update(tooltip: 'Oakline: 2 orders waiting');
  await DV.Platform.shortcuts.register(
    const DVGlobalShortcut(id: 'cart', accelerator: 'Ctrl+Shift+O'),
    onPressed: () => DV.Platform.window.open(DVRoutes.cart),
  );
}
// docs:end

// docs:start devices-drag-drop
// A drop zone is a modifier. Files, links and text dropped on it from
// another app arrive as one DVDropEvent, and so does a .draggable() dragged
// across from elsewhere in the app. Like every control it says what it is,
// and choosing a file does the same job for a keyboard or a screen reader.
Widget attachments(BuildContext context) {
  final DVSignal<String> attached = context.signal('Nothing attached yet');
  Future<void> attach(DVDropEvent event) async {
    final List<String> names = <String>[
      for (final DVIncomingFile file in event.files)
        '${file.name} (${(await file.readBytes()).length} bytes)',
      for (final Uri link in event.urls) '$link',
      if (event.text != null) event.text!,
    ];
    attached.value = names.join(', ');
  }

  return DVBox.list(<Widget>[
    const DVText('Drop receipts, links or notes here').modifier(
      DVModifier().padding(24).dropTarget(onDrop: attach),
    ),
    DVText(attached.value),
    DVText('Choose files instead').modifier(DVModifier().onTap(() async {
      final DVDropEvent? chosen = await DV.Platform.dragDrop.chooseInstead();
      if (chosen != null) await attach(chosen);
    })),
    DVText('Drag the cart link').modifier(DVModifier().draggable(
      DVDragPayload(urls: <Uri>[Uri.parse('https://oakline.example/cart')]),
    )),
  ]);
}
// docs:end
