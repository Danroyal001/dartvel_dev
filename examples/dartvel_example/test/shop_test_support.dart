// What the shop's screen tests share.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Pixel 6 in portrait, which is what the Android emulator job reports.
const Size phonePhysical = Size(1080, 2400);
const double phoneRatio = 2.625;

/// Frames rather than pumpAndSettle: a page that animates never settles, and
/// the shop opens its store asynchronously.
Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The real application at a [physical] size.
Future<void> pumpShop(
  WidgetTester tester, {
  Size physical = phonePhysical,
  double ratio = phoneRatio,
}) async {
  tester.view
    ..physicalSize = physical
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(createDartvelExampleApp());
  await settle(tester, 40);
}
