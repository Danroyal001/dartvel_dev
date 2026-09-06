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

@DVHomeWidget()
@DVFunctionalWidget()
Widget _orderStatusWidget(BuildContext context) => const DVBox.list(<Widget>[
      DVText('Order #4182'),
      DVText('Out for delivery'),
    ]);
