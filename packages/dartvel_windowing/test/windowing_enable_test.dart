// Enabling windowing has to replace the owner the binding already chose.
//
// WidgetsBinding picks its WindowingOwner when it is initialized, before any
// application code can set isWindowingEnabled, so it always starts with the
// "unsupported" owner. Setting the flag alone left that owner in place and
// every window controller threw "Windowing APIs are not enabled" on Flutter
// stable -- the projector window of a real app never opened.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports
@TestOn('linux')
library;

import 'package:dartvel_windowing/dartvel_windowing.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_linux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('enable installs the platform windowing owner', (tester) async {
    DVFlutterWindowSurfaceFactory.enable();

    final WindowingOwner owner = tester.binding.windowingOwner;
    expect(owner, isA<WindowingOwnerLinux>());
  });
}
