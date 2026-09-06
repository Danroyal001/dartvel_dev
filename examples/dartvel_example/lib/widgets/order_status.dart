// A home widget, so the build's native packaging has something to package.
//
// Every other part of @DVHomeWidget is covered by unit tests against
// temporary projects, and none of those proves what a real build does with
// one. The Android provider and its manifest receiver, and the WidgetKit
// extension with the Xcode target that builds it, only run for a project
// that actually declares a widget -- without one the packaging code ran on
// nothing in CI and every job was green either way.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';

// With a title, because the title is the half of the shell properties that
// leaves the application: it is what the launcher's picker and WidgetKit's
// gallery call this, and an untitled widget is offered as "order-status".
// It also keeps a build in CI exercising an annotation with arguments, which
// is the shape that used to make a home widget disappear.
@DVHomeWidget(title: 'Order status')
@DVFunctionalWidget()
Widget _orderStatusWidget(BuildContext context) => const DVBox.list(<Widget>[
      DVText('Order #4182'),
      DVText('Out for delivery'),
    ]);
